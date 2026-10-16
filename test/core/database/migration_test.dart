import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

/// Reads the current `schemaVersion` without leaving a database open.
Future<int> _currentSchemaVersion() async {
  final db = AppDatabase(NativeDatabase.memory());
  try {
    return db.schemaVersion;
  } finally {
    await db.close();
  }
}

/// Real schema-migration tests backed by committed drift snapshots
/// (architecture.md A4). Why: "zero data loss" is the product promise and
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
      expect(book.bookUid, 'uid-1');
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
    });
  });

  test('a committed snapshot exists for the current schemaVersion', () async {
    // Mechanical tripwire replacing the old hand-maintained one
    // (architecture.md A4): bumping schemaVersion without dumping a new
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
