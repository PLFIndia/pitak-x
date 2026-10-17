/// One-time legacy bookmarks → network rows migration (network domain use
/// case; libNetwork.md D8, §6 "Legacy prefs value", ADR 0012).
///
/// The old bookmarks feature stored a JSON array under the shared-preferences
/// key `library_bookmarks`. This use case moves that list into the network
/// table ONCE and then removes the key — after S4 there is exactly one list
/// of saved libraries (two lists would be two truths, D8).
///
/// Guarantees:
///  - **Idempotent**: only siteUrls the table does not know yet are inserted;
///    a second run (or a rerun after a crash between commit and key-clear)
///    inserts nothing new.
///  - **One transaction**: all inserts go through the repository's
///    `applyRefresh` bulk-insert path, so a crash can never store half the
///    old bookmarks.
///  - **The prefs key is cleared ONLY after the commit succeeded** — if the
///    insert fails, the old list is still on disk and the next start retries
///    (fail closed: never destroy the user's data before its replacement is
///    durable).
///  - **Order preserved**: migrated rows get ascending `sortOrder` values
///    appended after the existing rows, so the old bookmark order survives
///    (the repository sorts by `sortOrder` first).
///
/// Pure Dart: the prefs access arrives as function ports (the concrete
/// `LegacyBookmarksReader` lives in infrastructure and is wired in DI).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// One validated legacy bookmark handed over by the reader: the old
/// `LibraryBookmark(label, url)` shape (the reader re-implements that class's
/// `fromJson` validation rules — §6).
typedef LegacyBookmark = ({String label, String url});

/// Migrates the legacy prefs list into the network table.
final class MigrateLegacyBookmarksUseCase {
  /// Creates the use case over its ports. [readLegacy] returns the validated
  /// old bookmarks (empty when the key is absent or corrupt); [clearLegacy]
  /// removes the prefs key and reports whether that succeeded. [clock] is
  /// injectable for tests.
  MigrateLegacyBookmarksUseCase({
    required NetworkRepository repository,
    required Future<List<LegacyBookmark>> Function() readLegacy,
    required Future<bool> Function() clearLegacy,
    int Function()? clock,
  }) : _repository = repository,
       _readLegacy = readLegacy,
       _clearLegacy = clearLegacy,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NetworkRepository _repository;
  final Future<List<LegacyBookmark>> Function() _readLegacy;
  final Future<bool> Function() _clearLegacy;
  final int Function() _clock;

  /// Runs the migration. Right carries the number of rows inserted (0 = the
  /// key was absent/empty/everything already existed). Left is a storage
  /// failure — the prefs key then STAYS, so the next start retries.
  Future<Either<Failure, int>> call() async {
    final legacy = await _readLegacy();
    if (legacy.isEmpty) {
      // Absent, empty or fully corrupt: nothing to migrate. Clearing anyway
      // removes a corrupt value for good (and is a no-op when absent).
      await _clearLegacy();
      return right(0);
    }

    final existing = await _repository.loadAll();
    final known = <String>{for (final row in existing) row.siteUrl};
    var maxSort = 0;
    for (final row in existing) {
      if (row.sortOrder > maxSort) maxSort = row.sortOrder;
    }

    final now = _clock();
    final toInsert = <NetworkLibrary>[];
    for (final bookmark in legacy) {
      // Idempotency: skip URLs the table already knows (a previous partial
      // run, or the user re-added the library as a card/member since).
      if (!known.add(bookmark.url)) continue;
      maxSort++;
      toInsert.add(
        NetworkLibrary(
          siteUrl: bookmark.url,
          // The old label passed trim+length rules but not the §6 character
          // rules (bidi/control chars): degrade an unusable label to '' —
          // the descriptor fetch supplies the real name later.
          name: NetworkName.normalizeOrNull(bookmark.label) ?? '',
          // `source` defaults to `bookmark` — exactly what a migrated row is.
          createdAt: now,
          sortOrder: maxSort, // preserves the old bookmark order
        ),
      );
    }

    if (toInsert.isEmpty) {
      await _clearLegacy();
      return right(0);
    }

    // ONE transaction for all inserts: applyRefresh's `discovered` list is
    // exactly "insert these new rows atomically" (updated stays empty).
    final inserted = await _repository.applyRefresh(const [], toInsert);
    return inserted.match((failure) => left<Failure, int>(failure), (_) async {
      final cleared = await _clearLegacy();
      if (!cleared) {
        // The rows are committed but the key survived: report the failure
        // so the provider fails closed. The next run finds every URL
        // already present, inserts nothing and clears the key again —
        // harmless.
        return left<Failure, int>(
          const StorageFailure('legacy bookmarks key not cleared'),
        );
      }
      return right<Failure, int>(toInsert.length);
    });
  }
}
