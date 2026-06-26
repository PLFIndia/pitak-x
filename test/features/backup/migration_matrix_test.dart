/// Migration test matrix — the "zero data loss" contract (PLAN.md).
///
/// Asserts that EVERY column of the legacy Room `books` (25 cols, v10) and
/// `wishlist_books` (16 cols) survives a backup restore into Drift, byte-for-
/// byte. This is the Dart capstone of the data-loss guarantee; the vault half
/// is proven hermetically in Rust (`rust/tests/vault_fixture.rs`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import '../vault/vault_repository_write_stub.dart';

class _EmptyVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('matrix_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // A legacy books.db with EVERY v10 column populated with a distinct value.
  Uint8List booksDbAllColumns() {
    final path = '${tmp.path}/books.db';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE books(
          id INTEGER PRIMARY KEY NOT NULL, book_uid TEXT, title TEXT NOT NULL,
          title_transliteration TEXT, author TEXT,
          title_sort TEXT NOT NULL DEFAULT '',
          author_sort TEXT NOT NULL DEFAULT '', isbn TEXT, publisher TEXT,
          published_year INTEGER, genre TEXT, cover_url TEXT, page_count INTEGER,
          language TEXT, notes TEXT, location TEXT, source_type TEXT,
          source_detail TEXT, age_group TEXT, added_date INTEGER NOT NULL,
          copy_count INTEGER NOT NULL DEFAULT 1,
          needs_metadata INTEGER NOT NULL DEFAULT 0,
          removed INTEGER NOT NULL DEFAULT 0, removed_at INTEGER, added_by TEXT);
      ''')
      ..execute('''
        INSERT INTO books VALUES(
          42, 'uid-42', 'गोदान', 'Godaan', 'Premchand',
          'godaan-sort', 'premchand-sort', '9788126415236', 'Diamond',
          1936, 'Fiction', 'covers/abc.jpg', 384, 'hi', 'a classic',
          'Shelf 3', 'GIFT', 'from Ravi', 'advanced', 1699999999000,
          3, 1, 1, 1700000000000, 'Asha');
      ''')
      ..dispose();
    return File(path).readAsBytesSync();
  }

  // A legacy wishlist_books.db with EVERY column populated.
  Uint8List wishlistDbAllColumns() {
    final path = '${tmp.path}/wishlist.db';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE wishlist_books(
          id INTEGER PRIMARY KEY NOT NULL, title TEXT NOT NULL,
          title_transliteration TEXT, author TEXT, isbn TEXT, publisher TEXT,
          published_year INTEGER, cover_url TEXT, price_estimate REAL,
          priority INTEGER NOT NULL DEFAULT 1, notes TEXT, source TEXT NOT NULL,
          added_date INTEGER NOT NULL, purchased INTEGER NOT NULL DEFAULT 0,
          purchased_date INTEGER, needs_metadata INTEGER NOT NULL DEFAULT 0);
      ''')
      ..execute('''
        INSERT INTO wishlist_books VALUES(
          9, 'Wanted', 'Wanted-tr', 'Author W', '9991112223334', 'Pub W',
          2020, 'https://x/c.jpg', 19.99, 2, 'want it', 'SCANNED',
          1698000000000, 1, 1699000000000, 1);
      ''')
      ..dispose();
    return File(path).readAsBytesSync();
  }

  Uint8List archive(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((k, v) => a.addFile(ArchiveFile(k, v.length, v)));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  }

  RestoreBackup restorer() => RestoreBackup(
    db: db,
    vault: _EmptyVault(),
    coversDir: '${tmp.path}/covers',
    workDir: '${tmp.path}/work',
  );

  test('all 25 book columns survive restore byte-for-byte', () async {
    final zip = archive({
      'manifest.json': utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 1,
          'hasBackupBlob': false,
          'hasBorrowers': false,
        }),
      ),
      'books.db': booksDbAllColumns(),
      'wishlist.db': wishlistDbAllColumns(),
    });

    final p = SecretBytes(Uint8List.fromList([1]));
    final result = await restorer().restore(archiveBytes: zip, passphrase: p);
    p.dispose();
    result.getOrElse((f) => fail('restore failed: $f'));

    final b = (await db.select(db.books).get()).single;
    expect(b.id, 42);
    expect(b.bookUid, 'uid-42');
    expect(b.title, 'गोदान');
    expect(b.titleTransliteration, 'Godaan');
    expect(b.author, 'Premchand');
    // title_sort/author_sort are recomputed Unicode-aware shadows on persist.
    expect(b.titleSort, 'गोदान'.toLowerCase());
    expect(b.authorSort, 'premchand');
    expect(b.isbn, '9788126415236');
    expect(b.publisher, 'Diamond');
    expect(b.publishedYear, 1936);
    expect(b.genre, 'Fiction');
    expect(b.coverUrl, 'covers/abc.jpg');
    expect(b.pageCount, 384);
    expect(b.language, 'hi');
    expect(b.notes, 'a classic');
    expect(b.location, 'Shelf 3');
    expect(b.sourceType, 'GIFT');
    expect(b.sourceDetail, 'from Ravi');
    expect(b.ageGroup, 'advanced');
    expect(b.addedDate, 1699999999000);
    expect(b.copyCount, 3);
    expect(b.needsMetadata, isTrue);
    expect(b.removed, isTrue);
    expect(b.removedAt, 1700000000000);
    expect(b.addedBy, 'Asha');
  });

  test('all 16 wishlist columns survive restore byte-for-byte', () async {
    final zip = archive({
      'manifest.json': utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 1,
          'hasBackupBlob': false,
          'hasBorrowers': false,
        }),
      ),
      'books.db': booksDbAllColumns(),
      'wishlist.db': wishlistDbAllColumns(),
    });

    final p = SecretBytes(Uint8List.fromList([1]));
    final result = await restorer().restore(archiveBytes: zip, passphrase: p);
    p.dispose();
    result.getOrElse((f) => fail('restore failed: $f'));

    final w = (await db.select(db.wishlistBooks).get()).single;
    expect(w.id, 9);
    expect(w.title, 'Wanted');
    expect(w.titleTransliteration, 'Wanted-tr');
    expect(w.author, 'Author W');
    expect(w.isbn, '9991112223334');
    expect(w.publisher, 'Pub W');
    expect(w.publishedYear, 2020);
    expect(w.coverUrl, 'https://x/c.jpg');
    expect(w.priceEstimate, 19.99);
    expect(w.priority, 2);
    expect(w.notes, 'want it');
    expect(w.source, 'SCANNED');
    expect(w.addedDate, 1698000000000);
    expect(w.purchased, isTrue);
    expect(w.purchasedDate, 1699000000000);
    expect(w.needsMetadata, isTrue);
  });

  test('legacy v9 age ordinal token still imports (tolerant)', () async {
    // A pre-v10 fixture might carry a legacy age token; restore must tolerate.
    final path = '${tmp.path}/legacy_books.db';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE books(
          id INTEGER PRIMARY KEY NOT NULL, book_uid TEXT, title TEXT NOT NULL,
          title_transliteration TEXT, author TEXT,
          title_sort TEXT NOT NULL DEFAULT '',
          author_sort TEXT NOT NULL DEFAULT '', isbn TEXT, publisher TEXT,
          published_year INTEGER, genre TEXT, cover_url TEXT, page_count INTEGER,
          language TEXT, notes TEXT, location TEXT, source_type TEXT,
          source_detail TEXT, age_group TEXT, added_date INTEGER NOT NULL,
          copy_count INTEGER NOT NULL DEFAULT 1,
          needs_metadata INTEGER NOT NULL DEFAULT 0,
          removed INTEGER NOT NULL DEFAULT 0, removed_at INTEGER, added_by TEXT);
      ''')
      ..execute('''
        INSERT INTO books(id,title,age_group,added_date,copy_count,
          needs_metadata,removed)
        VALUES (1,'Old','age_11_16',1,1,0,0)
      ''')
      ..dispose();
    final zip = archive({
      'manifest.json': utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 1,
          'hasBackupBlob': false,
          'hasBorrowers': false,
          'hasWishlist': false,
        }),
      ),
      'books.db': File(path).readAsBytesSync(),
    });

    final p = SecretBytes(Uint8List.fromList([1]));
    final result = await restorer().restore(archiveBytes: zip, passphrase: p);
    p.dispose();
    result.getOrElse((f) => fail('restore failed: $f'));

    // Legacy 'age_11_16' maps to the v10 'above-10' token (MIGRATION_9_10).
    final b = (await db.select(db.books).get()).single;
    expect(b.ageGroup, 'above-10');
  });
}
