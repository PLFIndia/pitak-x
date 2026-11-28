/// Tests for the two Room-shaped SQLite files of a backup, written directly
/// (not through the whole archive writer).
///
/// Backup rework BR4, rider 1 (review finding P3-M1): each file is written
/// as ONE transaction. Before, every row was its own commit, which is slow
/// on a large library. The proof that does not depend on a clock: when one
/// row cannot be written, a single transaction leaves NOTHING behind, while
/// per-row commits would leave every row before the bad one.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/infrastructure/backup_room_databases.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_room_databases_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Opens the written file, runs [read], and always closes it again.
  T inDatabase<T>(String path, T Function(Database db) read) {
    final db = sqlite3.open(path);
    try {
      return read(db);
    } finally {
      db.dispose();
    }
  }

  /// How many tables called [table] the file at [path] holds (0 or 1).
  int tableCount(String path, String table) => inDatabase(
    path,
    (db) =>
        db.select(
              'SELECT count(*) AS n FROM sqlite_master '
              "WHERE type = 'table' AND name = ?",
              [table],
            ).single['n']
            as int,
  );

  /// The SQLite side files a write may leave next to [path].
  List<String> sideFiles(String path) => [
    for (final suffix in const ['-journal', '-wal', '-shm'])
      if (File('$path$suffix').existsSync()) suffix,
  ];

  group('books.db', () {
    const books = [
      CatalogueItem(id: 1, title: 'First', author: 'A', addedDate: 10),
      CatalogueItem(id: 2, title: 'Second', isbn: '9780000000002'),
      CatalogueItem(id: 7, title: 'Third', removed: true, removedAt: 30),
    ];

    test('holds every row in order, with the Room identity', () {
      final path = '${tmp.path}/books.db';
      writeRoomBooksDb(path, books);

      inDatabase(path, (db) {
        final rows = db.select(
          'SELECT id, title, author, isbn, added_date, removed, removed_at '
          'FROM books ORDER BY rowid',
        );
        expect(
          [for (final row in rows) (row['id'], row['title'])],
          [(1, 'First'), (2, 'Second'), (7, 'Third')],
        );
        expect(rows[0]['author'], 'A');
        expect(rows[0]['added_date'], 10);
        expect(rows[1]['isbn'], '9780000000002');
        expect(rows[2]['removed'], 1);
        expect(rows[2]['removed_at'], 30);

        expect(db.select('PRAGMA user_version').single.values.single, 9);
        final identity = db.select(
          'SELECT id, identity_hash FROM room_master_table',
        );
        expect(identity, hasLength(1));
        expect(identity.single['id'], 42);
        expect(
          identity.single['identity_hash'],
          matches(RegExp(r'^[0-9a-f]{32}$')),
        );
      });
    });

    test('an empty library gives the table with no rows', () {
      final path = '${tmp.path}/books.db';
      writeRoomBooksDb(path, const []);

      expect(tableCount(path, 'books'), 1);
      expect(tableCount(path, 'room_master_table'), 1);
      inDatabase(path, (db) {
        expect(db.select('SELECT id FROM books'), isEmpty);
      });
    });

    test('a row that cannot be written leaves nothing behind', () {
      final path = '${tmp.path}/books.db';

      // Two rows with the same id: the third insert breaks the primary key.
      expect(
        () => writeRoomBooksDb(path, const [
          CatalogueItem(id: 1, title: 'First'),
          CatalogueItem(id: 2, title: 'Second'),
          CatalogueItem(id: 2, title: 'Same id again'),
        ]),
        throwsA(isA<SqliteException>()),
      );

      // One transaction: the two good rows and the table itself are undone.
      expect(tableCount(path, 'books'), 0);
      expect(tableCount(path, 'room_master_table'), 0);
      expect(sideFiles(path), isEmpty);
    });

    test('leaves no SQLite side file next to the database', () {
      final path = '${tmp.path}/books.db';
      writeRoomBooksDb(path, books);

      expect(sideFiles(path), isEmpty);
    });
  });

  group('wishlist.db', () {
    const wishlist = [
      WishlistBook(id: 1, title: 'Wish one', author: 'W', addedDate: 5),
      WishlistBook(id: 3, title: 'Wish two', purchased: true, purchasedDate: 9),
    ];

    test('holds every row in order, with the Room identity', () {
      final path = '${tmp.path}/wishlist.db';
      writeRoomWishlistDb(path, wishlist);

      inDatabase(path, (db) {
        final rows = db.select(
          'SELECT id, title, author, added_date, purchased, purchased_date '
          'FROM wishlist_books ORDER BY rowid',
        );
        expect(
          [for (final row in rows) (row['id'], row['title'])],
          [(1, 'Wish one'), (3, 'Wish two')],
        );
        expect(rows[0]['author'], 'W');
        expect(rows[0]['added_date'], 5);
        expect(rows[1]['purchased'], 1);
        expect(rows[1]['purchased_date'], 9);

        expect(db.select('PRAGMA user_version').single.values.single, 1);
        final identity = db.select(
          'SELECT id, identity_hash FROM room_master_table',
        );
        expect(identity, hasLength(1));
        expect(identity.single['id'], 42);
      });
    });

    test('a row that cannot be written leaves nothing behind', () {
      final path = '${tmp.path}/wishlist.db';

      expect(
        () => writeRoomWishlistDb(path, const [
          WishlistBook(id: 1, title: 'Wish one'),
          WishlistBook(id: 1, title: 'Same id again'),
        ]),
        throwsA(isA<SqliteException>()),
      );

      expect(tableCount(path, 'wishlist_books'), 0);
      expect(tableCount(path, 'room_master_table'), 0);
      expect(sideFiles(path), isEmpty);
    });

    test('leaves no SQLite side file next to the database', () {
      final path = '${tmp.path}/wishlist.db';
      writeRoomWishlistDb(path, wishlist);

      expect(sideFiles(path), isEmpty);
    });
  });
}
