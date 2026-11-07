import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/sqlite_watched_libraries_source.dart';
import 'package:sqlite3/sqlite3.dart';

/// PLAN.md §2 / §8 "Read-only source": the background worker reads saved
/// libraries through its own read-only SQLite connection. These tests pin
/// the strict filter, the hard cap, fail-closed error handling, and — most
/// importantly — that the source never mutates the catalogue.
void main() {
  late Directory dir;
  late String dbPath;
  late AppDatabase db;
  late DriftNetworkRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('watched_source_test');
    dbPath = p.join(dir.path, 'pitaka.db');
    db = AppDatabase(NativeDatabase(File(dbPath)));
    repo = DriftNetworkRepository(db);
    // Force schema creation + close so the file is complete and unlocked.
    await repo.loadAll();
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  SqliteWatchedLibrariesSource source({String? Function()? resolve}) =>
      SqliteWatchedLibrariesSource(resolvePath: resolve ?? () => dbPath);

  Future<NetworkLibrary> save(
    String url, {
    NetworkSource src = NetworkSource.bookmark,
    String name = '',
    FetchStatus status = FetchStatus.never,
    int createdAt = 1000,
  }) async => (await repo.upsertBySiteUrl(
    NetworkLibrary(
      siteUrl: url,
      name: name,
      source: src,
      fetchStatus: status,
      createdAt: createdAt,
    ),
  )).toNullable()!;

  List<int> fileBytes() => File(dbPath).readAsBytesSync();

  group('snapshot', () {
    test('returns only bookmark/card rows, in URL order', () async {
      await save('https://c.github.io/lib/', src: NetworkSource.card);
      await save('https://a.github.io/lib/');
      await save('https://d.github.io/lib/', src: NetworkSource.discovered);
      await save('https://b.github.io/lib/');

      final rows = (await source().snapshot()).toNullable()!;

      expect(rows.map((r) => r.siteUrl), [
        'https://a.github.io/lib/',
        'https://b.github.io/lib/',
        'https://c.github.io/lib/',
      ]);
    });

    test('an unknown raw source token is NOT a saved library (the '
        'foreground repository would have mapped it to bookmark)', () async {
      final saved = await save('https://a.github.io/lib/');
      await db.customStatement(
        'UPDATE network_libraries SET source = ? WHERE id = ?',
        ['mystery', saved.id],
      );
      // Prove the foreground is permissive, so the strictness here matters.
      expect((await repo.loadAll()).single.source, NetworkSource.bookmark);

      final rows = (await source().snapshot()).toNullable()!;

      expect(rows, isEmpty);
    });

    test('publicName is set only when fetch_status is ok', () async {
      await save(
        'https://a.github.io/lib/',
        name: 'Public Name',
        status: FetchStatus.ok,
      );
      await save('https://b.github.io/lib/', name: 'Private label');
      await save(
        'https://c.github.io/lib/',
        name: 'Was ok once',
        status: FetchStatus.unreachable,
      );

      final rows = (await source().snapshot()).toNullable()!;

      expect(rows[0].publicName, 'Public Name');
      expect(rows[1].publicName, isNull);
      expect(rows[2].publicName, isNull);
    });

    test('an invalid stored name is never surfaced even when ok', () async {
      final saved = await save(
        'https://a.github.io/lib/',
        name: 'ok',
        status: FetchStatus.ok,
      );
      await db.customStatement(
        'UPDATE network_libraries SET name = ? WHERE id = ?',
        ['bad\u0000name', saved.id],
      );

      final rows = (await source().snapshot()).toNullable()!;

      expect(rows.single.publicName, isNull);
    });

    test('carries the full identity (id, createdAt, siteUrl)', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 4242);

      final row = (await source().snapshot()).toNullable()!.single;

      expect(row.identity.rowId, saved.id);
      expect(row.identity.createdAt, 4242);
      expect(row.identity.siteUrl, 'https://a.github.io/lib/');
    });

    test('exactly the cap is fine; one more is a visible CapacityFailure, '
        'never a silent subset', () async {
      for (var i = 0; i < maxWatchedLibraries; i++) {
        await save('https://l${i.toString().padLeft(3, '0')}.github.io/x/');
      }
      expect(
        (await source().snapshot()).toNullable()!.length,
        maxWatchedLibraries,
      );

      await save('https://overflow.github.io/x/');

      final result = await source().snapshot();
      expect(result.getLeft().toNullable(), isA<CapacityFailure>());
    });

    test(
      'a non-canonical site URL in the table fails the whole read',
      () async {
        final saved = await save('https://a.github.io/lib/');
        await db.customStatement(
          'UPDATE network_libraries SET site_url = ? WHERE id = ?',
          ['HTTPS://A.github.io/lib', saved.id],
        );

        final result = await source().snapshot();

        expect(result.getLeft().toNullable(), isA<StorageFailure>());
      },
    );
  });

  group('membership', () {
    test('a present, unchanged, user-saved row is stillWatched', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 7);
      final identity = WatchedLibraryIdentity(
        rowId: saved.id,
        createdAt: 7,
        siteUrl: saved.siteUrl,
      );

      final result = await source().membership(identity);

      expect(result.toNullable(), WatchedMembership.stillWatched);
    });

    test('a deleted row is removed', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 7);
      final identity = WatchedLibraryIdentity(
        rowId: saved.id,
        createdAt: 7,
        siteUrl: saved.siteUrl,
      );
      await repo.removeById(saved.id);

      final result = await source().membership(identity);

      expect(result.toNullable(), WatchedMembership.removed);
    });

    test('a row removed and re-added under the same URL is a DIFFERENT row: '
        'the old identity is removed', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 7);
      final old = WatchedLibraryIdentity(
        rowId: saved.id,
        createdAt: 7,
        siteUrl: saved.siteUrl,
      );
      await repo.removeById(saved.id);
      final again = await save('https://a.github.io/lib/', createdAt: 8);

      expect(
        (await source().membership(old)).toNullable(),
        WatchedMembership.removed,
      );
      expect(
        (await source().membership(
          WatchedLibraryIdentity(
            rowId: again.id,
            createdAt: 8,
            siteUrl: again.siteUrl,
          ),
        )).toNullable(),
        WatchedMembership.stillWatched,
      );
    });

    test('a source change to discovered (or unknown) is removed', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 7);
      final identity = WatchedLibraryIdentity(
        rowId: saved.id,
        createdAt: 7,
        siteUrl: saved.siteUrl,
      );
      for (final token in ['discovered', 'mystery']) {
        await db.customStatement(
          'UPDATE network_libraries SET source = ? WHERE id = ?',
          [token, saved.id],
        );
        expect(
          (await source().membership(identity)).toNullable(),
          WatchedMembership.removed,
          reason: token,
        );
      }
    });
  });

  group('no side effects', () {
    test('snapshot + membership leave the database file byte-identical and '
        'no journal behind', () async {
      final saved = await save('https://a.github.io/lib/', createdAt: 7);
      await db.close(); // make sure the foreground holds nothing open
      final before = fileBytes();

      final s = source();
      await s.snapshot();
      await s.membership(
        WatchedLibraryIdentity(
          rowId: saved.id,
          createdAt: 7,
          siteUrl: saved.siteUrl,
        ),
      );

      expect(fileBytes(), before);
      expect(File('$dbPath-journal').existsSync(), isFalse);
      expect(File('$dbPath-wal').existsSync(), isFalse);
      // Reopen so tearDown's close() has something to close.
      db = AppDatabase(NativeDatabase(File(dbPath)));
    });

    test(
      'an injected connection that tries to write is refused by SQLite '
      '(read-only + query_only) while the read itself still succeeds',
      () async {
        await save('https://a.github.io/lib/');
        final s = SqliteWatchedLibrariesSource(
          resolvePath: () => dbPath,
          open: (path) {
            final conn = sqlite3.open(path, mode: OpenMode.readOnly);
            // Simulate a future bug: a write attempt on this connection.
            expect(
              () => conn.execute('DELETE FROM network_libraries'),
              throwsA(isA<SqliteException>()),
            );
            return conn;
          },
        );

        final result = await s.snapshot();

        expect(result.isRight(), isTrue);
        expect((await repo.loadAll()).length, 1);
      },
    );
  });

  group('fail closed', () {
    test('no active generation → StorageFailure, nothing opened', () async {
      final result = await source(resolve: () => null).snapshot();

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
    });

    test('missing catalogue file → StorageFailure, file NOT created', () async {
      final missing = p.join(dir.path, 'nope.db');

      final result = await source(resolve: () => missing).snapshot();

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(File(missing).existsSync(), isFalse);
    });

    test('a database without the table → StorageFailure, no repair', () async {
      final empty = p.join(dir.path, 'empty.db');
      sqlite3.open(empty).dispose();
      final before = File(empty).readAsBytesSync();

      final result = await source(resolve: () => empty).snapshot();

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(File(empty).readAsBytesSync(), before);
    });

    test('generation switched during the read → StorageFailure', () async {
      await save('https://a.github.io/lib/');
      var calls = 0;
      final s = source(
        resolve: () => calls++ == 0 ? dbPath : p.join(dir.path, 'other.db'),
      );

      final result = await s.snapshot();

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
    });

    test('a foreground EXCLUSIVE lock makes the read fail closed within the '
        'busy timeout instead of hanging or guessing', () async {
      await save('https://a.github.io/lib/');
      await db.close();
      final writer = sqlite3.open(dbPath)..execute('BEGIN EXCLUSIVE');
      try {
        final s = SqliteWatchedLibrariesSource(
          resolvePath: () => dbPath,
          busyTimeoutMs: 50,
        );
        final stopwatch = Stopwatch()..start();

        final result = await s.snapshot();

        stopwatch.stop();
        expect(result.getLeft().toNullable(), isA<StorageFailure>());
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      } finally {
        writer
          ..execute('ROLLBACK')
          ..dispose();
        db = AppDatabase(NativeDatabase(File(dbPath)));
      }
    });

    test('after the lock is released the same source reads fine', () async {
      await save('https://a.github.io/lib/');
      await db.close();
      final writer = sqlite3.open(dbPath)..execute('BEGIN EXCLUSIVE');
      final s = SqliteWatchedLibrariesSource(
        resolvePath: () => dbPath,
        busyTimeoutMs: 50,
      );
      expect((await s.snapshot()).isLeft(), isTrue);
      writer
        ..execute('ROLLBACK')
        ..dispose();

      expect((await s.snapshot()).toNullable()!.length, 1);
      db = AppDatabase(NativeDatabase(File(dbPath)));
    });
  });
}
