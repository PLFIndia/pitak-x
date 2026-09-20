import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/database/app_database.dart';

/// The v1 database exactly as shipped: same tables, indexes and FTS, but
/// pinned to `schemaVersion 1` so a file it creates triggers `onUpgrade`
/// when the real [AppDatabase] opens it.
class _V1Database extends AppDatabase {
  _V1Database(super.executor);

  @override
  int get schemaVersion => 1;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('creates books with all 25 Room columns', () async {
    final cols = await db
        .customSelect('PRAGMA table_info(books)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(
      cols,
      containsAll(<String>[
        'id',
        'book_uid',
        'title',
        'title_transliteration',
        'author',
        'title_sort',
        'author_sort',
        'isbn',
        'publisher',
        'published_year',
        'genre',
        'cover_url',
        'page_count',
        'language',
        'notes',
        'location',
        'source_type',
        'source_detail',
        'age_group',
        'added_date',
        'copy_count',
        'needs_metadata',
        'removed',
        'removed_at',
        'added_by',
      ]),
    );
    expect(cols.length, 25);
  });

  test('creates wishlist_books with all 16 Room columns', () async {
    final cols = await db
        .customSelect('PRAGMA table_info(wishlist_books)')
        .map((r) => r.read<String>('name'))
        .get();
    expect(cols.length, 16);
    expect(cols, containsAll(<String>['price_estimate', 'purchased_date']));
  });

  test(
    'FTS5 index finds inserted books and stays in sync via triggers',
    () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'भारत: गांधी के बाद',
              addedDate: 1,
              titleTransliteration: const Value('Bharat Gandhi ke baad'),
              author: const Value('Ramachandra Guha'),
            ),
          );
      await db
          .into(db.books)
          .insert(BooksCompanion.insert(title: 'Wittgenstein', addedDate: 2));

      final hits = await db
          .customSelect(
            "SELECT rowid FROM books_fts WHERE books_fts MATCH 'Gandhi'",
          )
          .map((r) => r.read<int>('rowid'))
          .get();
      expect(hits, [1]);

      // Unicode title is searchable too.
      final uni = await db
          .customSelect(
            "SELECT rowid FROM books_fts WHERE books_fts MATCH 'गांधी'",
          )
          .get();
      expect(uni.length, 1);
    },
  );

  // Scaffold for schema migrations (REVIEW_FINDINGS_2 S3 / test-gap #8).
  // schemaVersion is 1 with onCreate only. When the FIRST bump lands, the
  // migration MUST ship with a forward-migration test in this group: create
  // a database file at the OLD version (raw sqlite3 DDL mirroring the old
  // schema — see restore_backup_test.dart's buildBooksDb for the pattern),
  // reopen it through AppDatabase so the migration runs, then assert the
  // data survived and the new schema objects exist. Bump the expectation
  // below in the same PR as the schemaVersion bump.
  group('schema migrations', () {
    test('schemaVersion tripwire — update with every bump', () {
      expect(
        AppDatabase(NativeDatabase.memory()).schemaVersion,
        2,
        reason:
            'schemaVersion changed without a migration test: add a '
            'forward-migration test to this group in the same PR.',
      );
    });

    group('v1 → v2: one spelling per language (Session 33)', () {
      late Directory tmp;
      late File dbFile;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('app_database_v2_test');
        dbFile = File(p.join(tmp.path, 'pitaka.db'));
      });

      tearDown(() => tmp.delete(recursive: true));

      Future<void> seedV1(List<(String title, String? language)> rows) async {
        final v1 = _V1Database(NativeDatabase(dbFile));
        for (final (title, language) in rows) {
          await v1
              .into(v1.books)
              .insert(
                BooksCompanion.insert(
                  title: title,
                  language: Value(language),
                  addedDate: 1,
                ),
              );
        }
        await v1.close();
      }

      Future<Map<String, int>> usage(AppDatabase db) async {
        final rows = await db
            .customSelect(
              'SELECT language, COUNT(*) AS n FROM books '
              'WHERE language IS NOT NULL GROUP BY language',
            )
            .get();
        return {
          for (final r in rows) r.read<String>('language'): r.read<int>('n'),
        };
      }

      test('collapses case variants and ISO codes; counts preserved', () async {
        await seedV1([
          ('a', 'English'),
          ('b', 'English'),
          ('c', 'english'),
          ('d', 'en'),
          ('e', 'Hindi'),
          ('f', 'hi'),
          ('g', null),
          // Non-Latin: grouped by Unicode case (SQLite lower() could not).
          ('h', 'Ελληνικά'),
          ('i', 'Ελληνικά'),
          ('j', 'ΕΛΛΗΝΙΚΆ'),
        ]);

        final v2 = AppDatabase(NativeDatabase(dbFile));
        addTearDown(v2.close);
        // Any query forces the open + migration.
        expect(await usage(v2), {'English': 4, 'Hindi': 2, 'Ελληνικά': 3});
        final version = await v2
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 2);
        // Every row survived; the language-less one is untouched.
        final total = await v2
            .customSelect('SELECT COUNT(*) AS n FROM books')
            .getSingle();
        expect(total.read<int>('n'), 10);
        final noLang = await v2
            .customSelect('SELECT title FROM books WHERE language IS NULL')
            .getSingle();
        expect(noLang.read<String>('title'), 'g');
      });

      test('keeps the dominant spelling even when lowercase', () async {
        await seedV1([('a', 'english'), ('b', 'english'), ('c', 'English')]);
        final v2 = AppDatabase(NativeDatabase(dbFile));
        addTearDown(v2.close);
        expect(await usage(v2), {'english': 3});
      });

      test('is a no-op on clean data and safe to re-open', () async {
        await seedV1([('a', 'English'), ('b', 'Hindi')]);
        final first = AppDatabase(NativeDatabase(dbFile));
        expect(await usage(first), {'English': 1, 'Hindi': 1});
        await first.close();
        // Second open is already v2: onUpgrade does not run; data unchanged.
        final second = AppDatabase(NativeDatabase(dbFile));
        addTearDown(second.close);
        expect(await usage(second), {'English': 1, 'Hindi': 1});
      });
    });

    test('a fresh database opens with the expected tables and FTS', () async {
      // Virtual tables (books_fts) appear in sqlite_master as type 'table'.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(tables, containsAll(['books', 'wishlist_books', 'books_fts']));
    });
  });

  test('ISBN unique index rejects duplicate non-null isbn', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'A',
            addedDate: 1,
            isbn: const Value('9780143104223'),
          ),
        );
    expect(
      () => db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              title: 'B',
              addedDate: 2,
              isbn: const Value('9780143104223'),
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });
}
