/// Writes the two Room-shaped SQLite files of a `.pitabak` backup:
/// `books.db` and `wishlist.db` (backup infrastructure).
///
/// Moved out of `backup_archive_writer.dart` on 2026-11-10 (backup rework
/// BR3), unchanged, when the writer's size checks pushed that file past the
/// 500-line ceiling. The split follows the writer's two jobs: this file
/// turns rows into SQLite files, the writer packs files into a ZIP.
///
/// Why the files are Room-shaped (beginner note): the archive format comes
/// from the retired Kotlin app, whose database library was Room. This app
/// keeps its catalogue in Drift, so it cannot copy a file; it writes fresh
/// SQLite files in the old shape from the current rows. The
/// `room_master_table` row and `user_version` keep that shape; they are NOT
/// a promise that Room would accept the file (see the library doc of
/// `backup_archive_writer.dart`).
///
/// Both functions run inside the backup worker isolate. They open SQLite
/// THEMSELVES through [_openSqlite]: the `sqlite3.open` tear-off cannot be
/// sent to an isolate (it drags a `NativeFinalizer` along).
///
/// Each file is written as ONE transaction (backup rework BR4, rider 1;
/// review finding P3-M1). See [_inOneTransaction] for why.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Room identity contract (from app/schemas) so the Kotlin app accepts our DBs.
const int _booksDbVersion = 9;
const String _booksIdentityHash = 'f4f033ebb290bd84fc04bd3d303d0e5f';
const int _wishlistDbVersion = 1;
const String _wishlistIdentityHash = 'ef4bdbbc39ca94fef44d980ecc902f28';

/// Opens (creating) a SQLite database file at [path]. Top-level on purpose:
/// the worker isolate calls it, and each isolate lazily builds its own
/// `sqlite3` binding, so no FFI handle ever has to cross the isolate boundary.
CommonDatabase _openSqlite(String path) => sqlite3.open(path);

/// Runs [write] as ONE SQLite transaction on [db].
///
/// WHY (beginner note): without `BEGIN`, SQLite treats every statement as
/// its own transaction and makes each one safe on disk before the next one
/// starts. For a library of thousands of rows that is thousands of small
/// waits for the disk. Between `BEGIN` and `COMMIT` the whole file is made
/// safe once, at the end.
///
/// It also makes the file all-or-nothing: when a row cannot be written,
/// `ROLLBACK` undoes the rows before it and the tables too. The backup
/// fails as a whole either way (the writer deletes its work folder), so
/// this is tidiness, not a new promise to the caller.
void _inOneTransaction(CommonDatabase db, void Function() write) {
  db.execute('BEGIN');
  try {
    write();
    db.execute('COMMIT');
  } on Object {
    // SQLite ends the transaction by itself after some errors (a full disk,
    // for one). `autocommit` is false only while a transaction is still
    // open, so this never asks for a rollback that would fail and hide the
    // real error.
    if (!db.autocommit) db.execute('ROLLBACK');
    rethrow;
  }
}

/// Writes a Room-compatible `books.db` with the books table and the Room
/// identity row, as one transaction. No FTS mirror is written (see the
/// library doc of `backup_archive_writer.dart` and the inline note):
/// the bundled SQLite lacks the FTS4 module and restore never reads it.
void writeRoomBooksDb(String path, List<CatalogueItem> books) {
  final db = _openSqlite(path);
  try {
    _inOneTransaction(db, () => _writeBooks(db, books));
  } finally {
    db.dispose();
  }
}

/// The statements of `books.db`: the version stamp, the table, one insert
/// per book and the Room identity row. Runs inside the transaction that
/// [writeRoomBooksDb] opens.
void _writeBooks(CommonDatabase db, List<CatalogueItem> books) {
  db
    ..execute('PRAGMA user_version = $_booksDbVersion')
    ..execute(
      'CREATE TABLE IF NOT EXISTS `books` ( '
      '`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `book_uid` TEXT, '
      '`title` TEXT NOT NULL, `title_transliteration` TEXT, `author` TEXT, '
      "`title_sort` TEXT NOT NULL DEFAULT '', "
      "`author_sort` TEXT NOT NULL DEFAULT '', "
      '`isbn` TEXT, `publisher` TEXT, `published_year` INTEGER, '
      '`genre` TEXT, `cover_url` TEXT, `page_count` INTEGER, '
      '`language` TEXT, `notes` TEXT, `location` TEXT, `source_type` TEXT, '
      '`source_detail` TEXT, `age_group` INTEGER, '
      '`added_date` INTEGER NOT NULL, '
      '`copy_count` INTEGER NOT NULL DEFAULT 1, '
      '`needs_metadata` INTEGER NOT NULL DEFAULT 0, '
      '`removed` INTEGER NOT NULL DEFAULT 0, `removed_at` INTEGER, '
      '`added_by` TEXT)',
    );
  // NOTE: no `books_fts` FTS4 mirror is written. The bundled on-device
  // SQLite (sqlite3_flutter_libs) has FTS5 only, so `USING FTS4` would
  // throw `no such module: fts4` and abort the backup. Our restore reader
  // never
  // reads this table — it rebuilds Drift's FTS independently — so omitting
  // it is correct for Pitak↔Pitak and Kotlin→Flutter restore.

  final stmt = db.prepare(
    'INSERT INTO `books`( '
    'id, book_uid, title, title_transliteration, author, title_sort, '
    'author_sort, isbn, publisher, published_year, genre, cover_url, '
    'page_count, language, notes, location, source_type, source_detail, '
    'age_group, added_date, copy_count, needs_metadata, removed, '
    'removed_at, added_by) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
  );
  try {
    for (final b in books) {
      stmt.execute([
        b.id,
        b.itemUid,
        b.title,
        b.titleTransliteration,
        b.author,
        '', // title_sort: NOT NULL DEFAULT '' (Room recomputes on use)
        '', // author_sort
        b.isbn,
        b.publisher,
        b.publishedYear,
        b.genre,
        b.coverUrl,
        b.pageCount,
        b.language,
        b.notes,
        b.location,
        b.sourceType?.token,
        b.sourceDetail,
        b.ageGroup?.token,
        b.addedDate,
        b.copyCount,
        _boolInt(b.needsMetadata),
        _boolInt(b.removed),
        b.removedAt,
        b.addedBy,
      ]);
    }
  } finally {
    stmt.dispose();
  }

  _writeRoomMaster(db, _booksIdentityHash);
}

/// Writes a Room-compatible `wishlist.db` with the wishlist_books table and
/// the Room identity row, as one transaction.
void writeRoomWishlistDb(String path, List<WishlistBook> wishlist) {
  final db = _openSqlite(path);
  try {
    _inOneTransaction(db, () => _writeWishlist(db, wishlist));
  } finally {
    db.dispose();
  }
}

/// The statements of `wishlist.db`: the version stamp, the table, one
/// insert per wish and the Room identity row. Runs inside the transaction
/// that [writeRoomWishlistDb] opens.
void _writeWishlist(CommonDatabase db, List<WishlistBook> wishlist) {
  db
    ..execute('PRAGMA user_version = $_wishlistDbVersion')
    ..execute(
      'CREATE TABLE IF NOT EXISTS `wishlist_books` ( '
      '`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      '`title` TEXT NOT NULL, `title_transliteration` TEXT, `author` TEXT, '
      '`isbn` TEXT, `publisher` TEXT, `published_year` INTEGER, '
      '`cover_url` TEXT, `price_estimate` REAL, '
      '`priority` INTEGER NOT NULL DEFAULT 1, `notes` TEXT, '
      '`source` TEXT NOT NULL, `added_date` INTEGER NOT NULL, '
      '`purchased` INTEGER NOT NULL DEFAULT 0, `purchased_date` INTEGER, '
      '`needs_metadata` INTEGER NOT NULL DEFAULT 0)',
    );
  final stmt = db.prepare(
    'INSERT INTO `wishlist_books`( '
    'id, title, title_transliteration, author, isbn, publisher, '
    'published_year, cover_url, price_estimate, priority, notes, source, '
    'added_date, purchased, purchased_date, needs_metadata) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
  );
  try {
    for (final w in wishlist) {
      stmt.execute([
        w.id,
        w.title,
        w.titleTransliteration,
        w.author,
        w.isbn,
        w.publisher,
        w.publishedYear,
        w.coverUrl,
        w.priceEstimate,
        w.priority,
        w.notes,
        w.source.token,
        w.addedDate,
        _boolInt(w.purchased),
        w.purchasedDate,
        _boolInt(w.needsMetadata),
      ]);
    }
  } finally {
    stmt.dispose();
  }
  _writeRoomMaster(db, _wishlistIdentityHash);
}

/// Writes Room's `room_master_table` identity row so Room's open-time
/// integrity check passes (id=42 is Room's fixed sentinel row).
void _writeRoomMaster(CommonDatabase db, String identityHash) {
  db
    ..execute(
      'CREATE TABLE IF NOT EXISTS room_master_table '
      '(id INTEGER PRIMARY KEY, identity_hash TEXT)',
    )
    ..execute(
      'INSERT OR REPLACE INTO room_master_table(id, identity_hash) '
      "VALUES (42, '$identityHash')",
    );
}

/// Room stores booleans as INTEGER 0/1.
int _boolInt(bool v) => v ? 1 : 0;
