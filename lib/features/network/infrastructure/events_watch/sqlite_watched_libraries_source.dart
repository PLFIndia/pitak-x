/// Read-only SQLite implementation of `WatchedLibrariesSource` for the
/// background event check (PLAN.md §2).
///
/// Design (beginner note on each rule):
///  - **Own connection, opened read-only, closed in `finally`.** The
///    foreground app owns the Drift connection and may be writing at any
///    moment. We never share it, never hold ours across network calls, and
///    never let SQLite's open path run migrations (`OpenMode.readOnly` cannot
///    create or alter anything).
///  - **Short busy wait, then fail closed.** The catalogue uses the default
///    rollback journal (decision 12: unchanged), so a foreground write blocks
///    readers briefly. We wait up to `busyTimeoutMs`; if still busy we return
///    a [StorageFailure] and the worker skips this site until the next run.
///    Skipping is harmless; guessing is not.
///  - **Strict raw-token filter.** The Drift repository maps unknown `source`
///    tokens to `bookmark` for display (`drift_network_repository.dart`).
///    Here an unknown token is NOT a saved library — the SQL itself only
///    matches the exact strings `bookmark` and `card`.
///  - **Generation re-check around every read.** The catalogue lives inside
///    the active data generation. If a restore switched generations while we
///    read, the rows we got belong to a data set the user just replaced; the
///    read is reported as failed rather than acted on.
///
/// The `sqlite3` read-only open is the same precedent `restore_backup.dart`
/// uses for its snapshot.
library;

import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Resolves the catalogue database path of the ACTIVE data generation
/// without side effects, or null when no trustworthy generation exists
/// (`DataGenerations.peekActive`).
typedef CatalogueDbPathResolver = String? Function();

/// Opens a database file read-only. Injectable so tests can inject faults.
typedef ReadOnlyDbOpener = CommonDatabase Function(String path);

CommonDatabase _defaultOpen(String path) =>
    sqlite3.open(path, mode: OpenMode.readOnly);

/// Raw `source` tokens that mean "the user saved this row" (PLAN.md
/// decision 2). Compared as exact strings inside SQL; `discovered` and any
/// unknown token are excluded.
const List<String> _savedSourceTokens = ['bookmark', 'card'];

/// Default busy wait. Long enough to outlast a typical single foreground
/// write, short enough that a stuck lock cannot eat the worker's deadline.
const int defaultBusyTimeoutMs = 250;

/// Read-only, bounded, strictly filtered reads of `network_libraries`.
final class SqliteWatchedLibrariesSource implements WatchedLibrariesSource {
  /// Creates a source over the catalogue resolved by [resolvePath].
  SqliteWatchedLibrariesSource({
    required CatalogueDbPathResolver resolvePath,
    int busyTimeoutMs = defaultBusyTimeoutMs,
    ReadOnlyDbOpener open = _defaultOpen,
  }) : _resolvePath = resolvePath,
       _busyTimeoutMs = busyTimeoutMs,
       _open = open;

  final CatalogueDbPathResolver _resolvePath;
  final int _busyTimeoutMs;
  final ReadOnlyDbOpener _open;

  @override
  Future<Either<Failure, List<WatchedLibrary>>> snapshot() async {
    return _withConnection((db) {
      // LIMIT cap+1 so we can tell "exactly at the cap" from "over it"
      // without counting the whole table.
      final rows = db.select(
        'SELECT id, site_url, created_at, name, fetch_status '
        'FROM network_libraries '
        'WHERE source IN (?, ?) '
        'ORDER BY site_url '
        'LIMIT ?',
        [..._savedSourceTokens, maxWatchedLibraries + 1],
      );
      if (rows.length > maxWatchedLibraries) {
        return left(const CapacityFailure('too many watched libraries'));
      }
      final libraries = <WatchedLibrary>[];
      for (final row in rows) {
        final library = _toWatchedLibrary(row);
        if (library == null) {
          // A row the foreground could never have written through its
          // validated path. Treat the whole read as untrustworthy rather
          // than fetch from whatever URL sits in that row.
          return left(const StorageFailure('watch row shape'));
        }
        libraries.add(library);
      }
      return right(libraries);
    });
  }

  @override
  Future<Either<Failure, WatchedMembership>> membership(
    WatchedLibraryIdentity identity,
  ) async {
    return _withConnection((db) {
      final rows = db.select(
        'SELECT source FROM network_libraries '
        'WHERE id = ? AND created_at = ? AND site_url = ? '
        'LIMIT 1',
        [identity.rowId, identity.createdAt, identity.siteUrl],
      );
      if (rows.isEmpty) return right(WatchedMembership.removed);
      final source = rows.first['source'];
      final saved = source is String && _savedSourceTokens.contains(source);
      return right(
        saved ? WatchedMembership.stillWatched : WatchedMembership.removed,
      );
    });
  }

  /// Opens, configures, runs [action], closes — and re-checks the active
  /// generation on both sides of the read. Every expected failure class
  /// becomes a [StorageFailure]; programming errors still propagate.
  Either<Failure, T> _withConnection<T>(
    Either<Failure, T> Function(CommonDatabase db) action,
  ) {
    final path = _resolvePath();
    if (path == null) return left(const StorageFailure('no active generation'));
    if (!File(path).existsSync()) {
      return left(const StorageFailure('catalogue missing'));
    }

    final CommonDatabase db;
    try {
      db = _open(path);
    } on SqliteException catch (e) {
      return left(StorageFailure('catalogue open ${e.resultCode}'));
    } on FileSystemException {
      return left(const StorageFailure('catalogue open io'));
    }

    try {
      // `query_only` is belt-and-braces on top of OpenMode.readOnly: even a
      // future bug that issued a write would be refused by SQLite itself.
      db
        ..execute('PRAGMA query_only = 1')
        ..execute('PRAGMA busy_timeout = $_busyTimeoutMs');
      final result = action(db);
      if (_resolvePath() != path) {
        return left(const StorageFailure('generation changed'));
      }
      return result;
    } on SqliteException catch (e) {
      // Busy/locked, hot journal (SQLITE_READONLY_ROLLBACK), missing table,
      // corrupt file: all "cannot read right now". None are repaired here.
      return left(StorageFailure('catalogue read ${e.resultCode}'));
    } on FileSystemException {
      return left(const StorageFailure('catalogue read io'));
    } finally {
      db.dispose();
    }
  }

  /// Maps one row to a [WatchedLibrary], or null when the row's shape or URL
  /// is not something the validated foreground path could have written.
  static WatchedLibrary? _toWatchedLibrary(Row row) {
    final id = row['id'];
    final siteUrl = row['site_url'];
    final createdAt = row['created_at'];
    final name = row['name'];
    final fetchStatus = row['fetch_status'];
    if (id is! int || siteUrl is! String || createdAt is! int) return null;
    if (BookmarkUrl.normalize(siteUrl) != siteUrl) return null;

    // Decision 13: only a descriptor-confirmed name may ever be displayed.
    final publicName = fetchStatus == 'ok' && name is String
        ? NetworkName.normalizeOrNull(name)
        : null;

    return WatchedLibrary(
      identity: WatchedLibraryIdentity(
        rowId: id,
        createdAt: createdAt,
        siteUrl: siteUrl,
      ),
      publicName: publicName,
    );
  }
}
