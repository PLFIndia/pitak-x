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
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:sqlite3/sqlite3.dart';

import '../vault/vault_repository_write_stub.dart';

/// A fake vault repo so the restore test never loads the native Rust lib.
class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  _FakeVault(this._result);
  final Either<Failure, VaultData> _result;
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => _result;
}

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SecretBytes pass() => SecretBytes(Uint8List.fromList([1, 2, 3]));

  // Builds a legacy Room books.db with the exact v10 column set.
  Uint8List buildBooksDb() {
    final path = '${tmp.path}/src_books.db';
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
        INSERT INTO books(id,book_uid,title,author,isbn,age_group,added_date,
          copy_count,needs_metadata,removed)
        VALUES (7,'uid-7','गोदान','Premchand','9788126415236',
          'advanced',1000,2,0,0)
      ''')
      ..dispose();
    return File(path).readAsBytesSync();
  }

  Uint8List buildWishlistDb() {
    final path = '${tmp.path}/src_wishlist.db';
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
        INSERT INTO wishlist_books(id,title,price_estimate,priority,source,
          added_date,purchased)
        VALUES (3,'Wanted',12.5,2,'SCANNED',500,0)
      ''')
      ..dispose();
    return File(path).readAsBytesSync();
  }

  Uint8List archive(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((k, v) => a.addFile(ArchiveFile(k, v.length, v)));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  }

  String manifest({int schemaVersion = 1, bool hasBackupBlob = false}) =>
      jsonEncode({
        'schemaVersion': schemaVersion,
        'exportedAt': 123,
        'hasBooks': true,
        'hasWishlist': true,
        'hasBorrowers': hasBackupBlob,
        'hasBackupBlob': hasBackupBlob,
        'hasCovers': false,
      });

  RestoreBackup restorer(VaultRepository vault) => RestoreBackup(
    db: db,
    vault: vault,
    coversDir: '${tmp.path}/covers',
    workDir: '${tmp.path}/work',
  );

  test('restores books + wishlist preserving id and uid', () async {
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });

    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    final summary = result.getOrElse((f) => fail('unexpected failure: $f'));
    expect(summary.booksRestored, 1);
    expect(summary.wishlistRestored, 1);
    expect(summary.isIntact, isTrue);

    // Preserved id + uid + Unicode title in the live Drift DB.
    final books = await db.select(db.books).get();
    expect(books.single.id, 7);
    expect(books.single.bookUid, 'uid-7');
    expect(books.single.title, 'गोदान');
    expect(books.single.copyCount, 2);

    final wishlist = await db.select(db.wishlistBooks).get();
    expect(wishlist.single.id, 3);
    expect(wishlist.single.priceEstimate, 12.5);
  });

  test('FTS search works after restore (rebuildFts ran)', () async {
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    final hits = await db
        .customSelect(
          'SELECT b.id FROM books_fts f JOIN books b ON b.id = f.rowid '
          'WHERE books_fts MATCH ?1',
          variables: [const Variable<String>('"Premchand"*')],
        )
        .get();
    expect(hits.single.read<int>('id'), 7);
  });

  test('authoritative overwrite wipes pre-existing rows', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'OLD',
            addedDate: 1,
            bookUid: const Value('old'),
          ),
        );
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    final books = await db.select(db.books).get();
    expect(books.length, 1);
    expect(books.single.bookUid, 'uid-7'); // OLD row gone
  });

  test('refuses a manifest schemaVersion newer than known', () async {
    final zip = archive({
      'manifest.json': utf8.encode(manifest(schemaVersion: 99)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    result.match(
      (f) => expect(f, isA<SchemaTooNewFailure>()),
      (_) => fail('expected schema-too-new'),
    );
    // No device writes on a pre-write failure.
    expect(await db.select(db.books).get(), isEmpty);
  });

  test('wrong passphrase aborts before any device write', () async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'KEEP',
            addedDate: 1,
            bookUid: const Value('keep'),
          ),
        );
    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
      'borrowers.db': [1, 2, 3],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });
    final r = restorer(_FakeVault(left(const WrongPassphraseFailure())));
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    result.match(
      (f) => expect(f, isA<WrongPassphraseFailure>()),
      (_) => fail('expected wrong-passphrase'),
    );
    // Pre-existing row must be untouched (overwrite never happened).
    final books = await db.select(db.books).get();
    expect(books.single.bookUid, 'keep');
  });

  test('surfaces dangling loans from cross-DB integrity check', () async {
    final vault = _FakeVault(
      right(
        const VaultData(
          borrowers: [Borrower(id: 1, name: 'Asha')],
          loans: [
            Loan(bookId: 999, borrowerId: 1, lentDate: 1), // book 999 missing
          ],
        ),
      ),
    );
    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
      'borrowers.db': [1, 2, 3],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });
    final r = restorer(vault);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    final summary = result.getOrElse((f) => fail('unexpected: $f'));
    expect(summary.loansRestored, 1);
    expect(summary.isIntact, isFalse);
    expect(summary.danglingLoans.single.missingBook, isTrue);
  });

  test('missing manifest is a corrupt archive', () async {
    final zip = archive({'books.db': buildBooksDb()});
    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();
    result.match(
      (f) => expect(f, isA<BackupCorruptFailure>()),
      (_) => fail('expected corrupt'),
    );
  });
}
