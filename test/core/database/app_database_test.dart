import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';

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
        1,
        reason:
            'schemaVersion changed without a migration test: add a '
            'forward-migration test to this group in the same PR.',
      );
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
