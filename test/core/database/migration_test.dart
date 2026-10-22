import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

/// Reads the current `schemaVersion` without leaving a database open.
Future<int> _currentSchemaVersion() async {
  final db = AppDatabase(NativeDatabase.memory());
  try {
    return db.schemaVersion;
  } finally {
    await db.close();
  }
}

/// The schema objects drift's snapshots cannot see — created by raw SQL in
/// `AppDatabase._createIndexesAndFts`. A migration that rebuilt `books`
/// would drop the triggers with it, so every upgrade path must end with all
/// of them present (type → names).
const _rawSqlObjects = <String, List<String>>{
  'table': ['books_fts'],
  'index': [
    'index_books_isbn',
    'index_books_book_uid',
    'index_books_added_date',
    'index_books_title_sort',
    'index_books_author_sort',
    'index_wishlist_books_isbn',
    // Schema v5 (ADR 0013): kind facet, issue identity keys, periodical ids.
    'index_books_kind',
    'index_magazine_issues_periodical_uid',
    'index_magazine_issues_number_key',
    'index_magazine_issues_bound_key',
    'index_periodicals_periodical_uid',
    'index_periodicals_issn',
  ],
  'trigger': ['books_fts_ai', 'books_fts_ad', 'books_fts_au'],
};

/// Asserts the raw-SQL objects exist AND search actually works — presence
/// alone would not catch a trigger left pointing at a rebuilt table.
///
/// Two probes: [migratedTitleWord], when given, is a word from a row that
/// existed BEFORE the upgrade and proves the index covers pre-existing rows
/// (the typed data-matrix tests supply it); a row inserted AFTER the upgrade
/// proves the sync triggers are live.
Future<void> _expectRawSqlObjectsHealthy(
  AppDatabase db, {
  String? migratedTitleWord,
}) async {
  for (final entry in _rawSqlObjects.entries) {
    final names = await db
        .customSelect(
          'SELECT name FROM sqlite_master WHERE type = ?',
          variables: [Variable(entry.key)],
        )
        .map((r) => r.read<String>('name'))
        .get();
    expect(
      names,
      containsAll(entry.value),
      reason: 'missing ${entry.key}(s) after migration',
    );
  }

  Future<int> hitsFor(String word) async {
    final rows = await db
        .customSelect(
          'SELECT rowid FROM books_fts WHERE books_fts MATCH ?',
          variables: [Variable(word)],
        )
        .get();
    return rows.length;
  }

  if (migratedTitleWord != null) {
    expect(
      await hitsFor(migratedTitleWord),
      greaterThan(0),
      reason: 'FTS5 does not find a row that existed before the upgrade',
    );
  }
  await db
      .into(db.books)
      .insert(
        BooksCompanion.insert(title: 'Trigger Probe', addedDate: 1700000009000),
      );
  expect(
    await hitsFor('Probe'),
    1,
    reason: 'FTS5 insert trigger is not live after the upgrade',
  );
}

/// Real schema-migration tests backed by committed drift snapshots
/// (docs/ARCHITECTURE.md §5.4). Why: "zero data loss" is the product promise and
/// F-Droid users update irregularly, so v1→vN jumps must be proven against
/// the *actual historical schemas* — not a fabricated in-test database.
///
/// Adding a schema version (rule, also in README › Quality gates):
///   1. bump `schemaVersion` in app_database.dart,
///   2. `dart run drift_dev schema dump lib/core/database/app_database.dart
///      drift_schemas/app_database/`,
///   3. `dart run drift_dev schema generate --data-classes --companions
///      drift_schemas/app_database test/core/database/generated/`,
///   4. add a row to the data matrix below.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('every historical version migrates to the current schema', () async {
    final current = await _currentSchemaVersion();
    for (var from = 1; from <= current - 1; from++) {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection.executor);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, current);
      // The snapshot carries only drift-visible objects; the upgrade must
      // leave the raw-SQL ones (indexes, FTS5, triggers) present and live.
      await _expectRawSqlObjectsHealthy(db);
    }
  });

  group('data matrix — one fully-populated row per version', () {
    test('v1: books + wishlist rows survive the migration to v2', () async {
      final schema = await verifier.schemaAt(1);
      final oldDb = v1.DatabaseAtV1(schema.newConnection());

      // Fully populated: every column set to a recognisable value.
      await oldDb
          .into(oldDb.books)
          .insert(
            v1.BooksCompanion.insert(
              // The v1 helper is generated from the v1 snapshot and keeps the
              // getter name of that era (`bookUid`); only the live schema's
              // getter was renamed `itemUid` (plan F7).
              bookUid: const Value('uid-1'),
              title: 'The Migration Book',
              titleTransliteration: const Value('Migration Book'),
              author: const Value('A. Writer'),
              titleSort: const Value('Migration Book, The'),
              authorSort: const Value('Writer, A.'),
              isbn: const Value('9780143104223'),
              publisher: const Value('Test Publisher'),
              publishedYear: const Value(1999),
              genre: const Value('fiction'),
              coverUrl: const Value('https://example.test/cover.jpg'),
              pageCount: const Value(321),
              language: const Value('English'),
              notes: const Value('a note'),
              location: const Value('shelf-3'),
              sourceType: const Value('manual'),
              sourceDetail: const Value('typed in'),
              ageGroup: const Value('adult'),
              addedDate: 1700000000000,
              copyCount: const Value(2),
              needsMetadata: const Value(false),
              removed: const Value(false),
              addedBy: const Value('tester'),
            ),
          );
      await oldDb
          .into(oldDb.wishlistBooks)
          .insert(
            v1.WishlistBooksCompanion.insert(
              title: 'The Wishlist Book',
              titleTransliteration: const Value('Wishlist Book'),
              author: const Value('W. Author'),
              isbn: const Value('9780143104224'),
              publisher: const Value('Wish Publisher'),
              publishedYear: const Value(2001),
              coverUrl: const Value('https://example.test/wish.jpg'),
              priceEstimate: const Value(19.99),
              priority: const Value(1),
              notes: const Value('wish note'),
              source: const Value('friend'),
              addedDate: 1700000001000,
              purchased: const Value(false),
              needsMetadata: const Value(false),
            ),
          );
      await oldDb.close();

      // Migrate to the current version through the real AppDatabase.
      final current = await _currentSchemaVersion();
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, current);

      final book = await db.select(db.books).getSingle();
      expect(book.itemUid, 'uid-1');
      expect(book.title, 'The Migration Book');
      expect(book.titleTransliteration, 'Migration Book');
      expect(book.author, 'A. Writer');
      expect(book.titleSort, 'Migration Book, The');
      expect(book.authorSort, 'Writer, A.');
      expect(book.isbn, '9780143104223');
      expect(book.publisher, 'Test Publisher');
      expect(book.publishedYear, 1999);
      expect(book.genre, 'fiction');
      expect(book.coverUrl, 'https://example.test/cover.jpg');
      expect(book.pageCount, 321);
      expect(book.language, 'English');
      expect(book.notes, 'a note');
      expect(book.location, 'shelf-3');
      expect(book.sourceType, 'manual');
      expect(book.sourceDetail, 'typed in');
      expect(book.ageGroup, 'adult');
      expect(book.addedDate, 1700000000000);
      expect(book.copyCount, 2);
      expect(book.needsMetadata, false);
      expect(book.removed, false);
      expect(book.removedAt, isNull);
      expect(book.addedBy, 'tester');

      final wish = await db.select(db.wishlistBooks).getSingle();
      expect(wish.title, 'The Wishlist Book');
      expect(wish.titleTransliteration, 'Wishlist Book');
      expect(wish.author, 'W. Author');
      expect(wish.isbn, '9780143104224');
      expect(wish.publisher, 'Wish Publisher');
      expect(wish.publishedYear, 2001);
      expect(wish.coverUrl, 'https://example.test/wish.jpg');
      expect(wish.priceEstimate, 19.99);
      expect(wish.priority, 1);
      expect(wish.notes, 'wish note');
      expect(wish.source, 'friend');
      expect(wish.addedDate, 1700000001000);
      expect(wish.purchased, false);
      expect(wish.purchasedDate, isNull);
      expect(wish.needsMetadata, false);

      await _expectRawSqlObjectsHealthy(db, migratedTitleWord: 'Migration');
    });

    test('v2 rows re-read through the current database unchanged', () async {
      // The v2 → v2 path: a snapshot row at the current version must round-
      // trip exactly (guards the matrix against drift in the snapshots).
      final schema = await verifier.schemaAt(2);
      final oldDb = v2.DatabaseAtV2(schema.newConnection());
      await oldDb
          .into(oldDb.books)
          .insert(
            v2.BooksCompanion.insert(
              title: 'Current Book',
              addedDate: 1700000002000,
              isbn: const Value('9780143104225'),
            ),
          );
      await oldDb.close();

      final current = await _currentSchemaVersion();
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, current);
      final book = await db.select(db.books).getSingle();
      expect(book.title, 'Current Book');
      expect(book.isbn, '9780143104225');

      await _expectRawSqlObjectsHealthy(db, migratedTitleWord: 'Current');
    });

    // Data-matrix row for the v3 bump (docs/ARCHITECTURE.md §5.4, README › Schema
    // version bumps): the new table must exist and start EMPTY on upgrade —
    // the legacy bookmarks data migration is a separate prefs→rows step
    // (S4), never part of the SQL migration.
    test(
      'v2: books + wishlist survive; network_libraries exists and is empty',
      () async {
        final schema = await verifier.schemaAt(2);
        final oldDb = v2.DatabaseAtV2(schema.newConnection());
        await oldDb
            .into(oldDb.books)
            .insert(
              v2.BooksCompanion.insert(
                title: 'Upgrade Survivor',
                addedDate: 1700000003000,
              ),
            );
        await oldDb
            .into(oldDb.wishlistBooks)
            .insert(
              v2.WishlistBooksCompanion.insert(
                title: 'Wish Survivor',
                addedDate: 1700000004000,
              ),
            );
        await oldDb.close();

        final current = await _currentSchemaVersion();
        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, current);

        expect(
          (await db.select(db.books).get()).single.title,
          'Upgrade Survivor',
        );
        expect(
          (await db.select(db.wishlistBooks).get()).single.title,
          'Wish Survivor',
        );
        expect(await db.select(db.networkLibraries).get(), isEmpty);
        expect(await db.select(db.networkLibraries).get(), isA<List<Object>>());

        await _expectRawSqlObjectsHealthy(db, migratedTitleWord: 'Upgrade');
      },
    );

    // Data-matrix row for the v4 bump (design 2026-10-18): a populated v3
    // network row must survive, and the new `confirmed_by_member` column
    // reads as false until the next refresh re-evaluates the link-back.
    test(
      'v3: a network row survives; confirmed_by_member defaults to false',
      () async {
        final schema = await verifier.schemaAt(3);
        final oldDb = v3.DatabaseAtV3(schema.newConnection());
        await oldDb
            .into(oldDb.networkLibraries)
            .insert(
              v3.NetworkLibrariesCompanion.insert(
                siteUrl: 'https://m.github.io/x/',
                name: const Value('Listed Member'),
                fingerprint: Value('ab' * 32),
                source: 'discovered',
                listedByHubUrl: const Value('https://hub.github.io/h/'),
                createdAt: 1700000005000,
                sortOrder: 0,
              ),
            );
        await oldDb.close();

        final current = await _currentSchemaVersion();
        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, current);

        final row = (await db.select(db.networkLibraries).get()).single;
        expect(row.name, 'Listed Member');
        expect(row.listedByHubUrl, 'https://hub.github.io/h/');
        expect(row.confirmedByMember, isFalse);

        await _expectRawSqlObjectsHealthy(db);
      },
    );

    // Data-matrix row for the v5 bump (ADR 0013): a populated v4 catalogue
    // survives with `kind` back-filled to `book`; the FTS index is rebuilt
    // WITH `notes` (a notes-only word is found; the column list is asserted);
    // the new tables exist, start empty, and the detail table cascades from
    // its base row; every kind round-trips through the current schema.
    test(
      'v4: books survive as kind=book, FTS gains notes, kinds round-trip',
      () async {
        final schema = await verifier.schemaAt(4);
        final oldDb = v4.DatabaseAtV4(schema.newConnection());
        await oldDb
            .into(oldDb.books)
            .insert(
              v4.BooksCompanion.insert(
                bookUid: const Value('uid-v4'),
                title: 'Pre-upgrade Book',
                notes: const Value('zebra in the notes only'),
                addedDate: 1700000006000,
              ),
            );
        await oldDb.close();

        final current = await _currentSchemaVersion();
        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, current);

        // Back-fill: the pre-upgrade row is a book.
        final book = await db.select(db.books).getSingle();
        expect(book.title, 'Pre-upgrade Book');
        expect(book.itemUid, 'uid-v4');
        expect(book.kind, 'book');
        expect(await db.select(db.periodicals).get(), isEmpty);
        expect(await db.select(db.magazineIssues).get(), isEmpty);

        // D10: the rebuilt index covers notes — a word that appears ONLY in
        // the notes of a pre-upgrade row is found.
        final ftsColumns = await db
            .customSelect('PRAGMA table_info(books_fts)')
            .map((r) => r.read<String>('name'))
            .get();
        expect(ftsColumns, [
          'title',
          'title_transliteration',
          'author',
          'isbn',
          'location',
          'genre',
          'notes',
        ]);
        await _expectRawSqlObjectsHealthy(db, migratedTitleWord: 'zebra');

        // Every kind round-trips: a periodical, a numbered issue, a bound
        // volume and an "other" item, written through the current schema.
        await db
            .into(db.periodicals)
            .insert(
              PeriodicalsCompanion.insert(
                periodicalUid: 'p-1',
                title: 'Chandamama',
                issn: const Value('0317-8471'),
                frequency: const Value('monthly'),
                addedDate: 1700000007000,
              ),
            );
        final issueId = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Chandamama — No 1',
                addedDate: 1700000008000,
                kind: const Value('magazine-issue'),
              ),
            );
        await db
            .into(db.magazineIssues)
            .insert(
              MagazineIssuesCompanion.insert(
                itemId: Value(issueId),
                periodicalUid: 'p-1',
                issueNumber: const Value(1),
              ),
            );
        final boundId = await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Chandamama — Jan 2025 – Dec 2025',
                addedDate: 1700000008001,
                kind: const Value('magazine-issue'),
              ),
            );
        await db
            .into(db.magazineIssues)
            .insert(
              MagazineIssuesCompanion.insert(
                itemId: Value(boundId),
                periodicalUid: 'p-1',
                issueDate: const Value(1735689600000),
                boundUntil: const Value(1764547200000),
              ),
            );
        await db
            .into(db.books)
            .insert(
              BooksCompanion.insert(
                title: 'Carrom board',
                addedDate: 1700000008002,
                kind: const Value('other'),
              ),
            );
        final kinds = await db
            .customSelect('SELECT kind, COUNT(*) AS n FROM books GROUP BY kind')
            .map((r) => '${r.read<String>('kind')}=${r.read<int>('n')}')
            .get();
        // `Trigger Probe` (inserted by the health check) is a book too.
        expect(kinds, containsAll(['book=2', 'magazine-issue=2', 'other=1']));
        final periodical = await db.select(db.periodicals).getSingle();
        expect(periodical.issn, '0317-8471');
        expect(periodical.frequency, 'monthly');
        expect(periodical.removed, isFalse);

        // D6 identity keys: the partial UNIQUE indexes refuse a second
        // numbered issue with the same key (no volume == volume 0) and a
        // second bound volume with the same range.
        await expectLater(
          db
              .into(db.magazineIssues)
              .insert(
                MagazineIssuesCompanion.insert(
                  itemId: Value(
                    await db
                        .into(db.books)
                        .insert(
                          BooksCompanion.insert(
                            title: 'dup number',
                            addedDate: 1,
                            kind: const Value('magazine-issue'),
                          ),
                        ),
                  ),
                  periodicalUid: 'p-1',
                  volume: const Value(0),
                  issueNumber: const Value(1),
                ),
              ),
          throwsA(isA<Object>()),
          reason: 'UNIQUE (periodical_uid, COALESCE(volume,0), issue_number)',
        );
        await expectLater(
          db
              .into(db.magazineIssues)
              .insert(
                MagazineIssuesCompanion.insert(
                  itemId: Value(
                    await db
                        .into(db.books)
                        .insert(
                          BooksCompanion.insert(
                            title: 'dup bound',
                            addedDate: 2,
                            kind: const Value('magazine-issue'),
                          ),
                        ),
                  ),
                  periodicalUid: 'p-1',
                  issueDate: const Value(1735689600000),
                  boundUntil: const Value(1764547200000),
                ),
              ),
          throwsA(isA<Object>()),
          reason: 'UNIQUE (periodical_uid, issue_date, bound_until)',
        );

        // F4 cascade: deleting the base row deletes its detail row (proves
        // `PRAGMA foreign_keys = ON` is live on this connection).
        await (db.delete(db.books)..where((t) => t.id.equals(issueId))).go();
        final details = await db.select(db.magazineIssues).get();
        expect(details.map((d) => d.itemId), [boundId]);
      },
    );
  });

  test('a committed snapshot exists for the current schemaVersion', () async {
    // Mechanical tripwire replacing the old hand-maintained one
    // (docs/ARCHITECTURE.md §5.4): bumping schemaVersion without dumping a new
    // snapshot fails here. Reads the JSON file itself (not just the generated
    // helper) so deleting the snapshot breaks the test immediately.
    final current = await _currentSchemaVersion();
    expect(
      GeneratedHelper.versions,
      contains(current),
      reason:
          'schemaVersion is $current but the generated helper has no v$current '
          '— regenerate (see the comment at the top of this file).',
    );
    final snapshot = File(
      'drift_schemas/app_database/drift_schema_v$current.json',
    );
    expect(
      snapshot.existsSync(),
      isTrue,
      reason:
          'schemaVersion is $current but ${snapshot.path} is missing — dump '
          'it (see the comment at the top of this file).',
    );
  });
}
