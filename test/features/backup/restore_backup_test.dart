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
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/book_mapper.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
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

/// An [AppDatabase] whose FTS rebuild always fails, for the restore
/// rollback regression (REVIEW_FINDINGS_2 S10).
class _FtsFailingDb extends AppDatabase {
  _FtsFailingDb(super.executor);

  @override
  Future<void> rebuildFts() async => throw StateError('fts rebuild boom');
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

  VaultStore vaultStore() => VaultStore(baseDir: '${tmp.path}/vault');

  RestoreBackup restorer(VaultRepository vault, [VaultStore? store]) =>
      RestoreBackup(
        db: db,
        vault: vault,
        vaultStore: store ?? vaultStore(),
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

  // Regression for REVIEW_FINDINGS_2 S10: rebuildFts used to run AFTER the
  // library transaction committed but inside the same try — a rebuild failure
  // aborted the staged vault and reported failure while the new library
  // stayed committed (new library + old vault + a lying error message). Now
  // it runs INSIDE the transaction, so a failure rolls everything back and
  // the reported result matches the device state.
  test('an FTS-rebuild failure rolls the whole restore back', () async {
    final failingDb = _FtsFailingDb(NativeDatabase.memory());
    addTearDown(failingDb.close);
    // Pre-restore device state: one existing book.
    await failingDb
        .into(failingDb.books)
        .insert(const Book(title: 'PreExisting', addedDate: 1).toCompanion());

    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = RestoreBackup(
      db: failingDb,
      vault: _FakeVault(right(VaultData.empty)),
      vaultStore: vaultStore(),
      coversDir: '${tmp.path}/covers',
      workDir: '${tmp.path}/work',
    );
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<StorageFailure>());
    // Reported failure == device state: fully pre-restore.
    final books = await failingDb.select(failingDb.books).get();
    expect(books.map((b) => b.title), ['PreExisting']);
    final wishlist = await failingDb.select(failingDb.wishlistBooks).get();
    expect(wishlist, isEmpty);
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

  test('C1: persists the restored vault to the live VaultStore', () async {
    final store = vaultStore();
    // The fake vault doesn't open the DB, so its exact bytes are opaque here;
    // we only assert they are installed at the live path verbatim.
    final borrowersBytes = Uint8List.fromList([10, 20, 30, 40]);
    const blob = 'salt.iv.ct';
    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
      'borrowers.db': borrowersBytes,
      'backup_blob': utf8.encode(blob),
    });
    final vault = _FakeVault(
      right(
        const VaultData(
          borrowers: [Borrower(id: 1, name: 'Asha')],
          loans: [],
        ),
      ),
    );
    final r = restorer(vault, store);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isRight(), isTrue);
    // Before C1 this was false: the vault was read for counts then discarded.
    expect(store.isInitialized(), isTrue);
    expect(File(store.dbPath).readAsBytesSync(), borrowersBytes);
    expect(store.readBlob(), blob);
  });

  test('vault staging failure aborts BEFORE the library overwrite', () async {
    // Pre-restore library row that must survive a failed restore.
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'KEEP',
            addedDate: 1,
            bookUid: const Value('keep'),
          ),
        );
    // Sabotage the store: its baseDir path is occupied by a FILE, so
    // stageRestore's createSync(recursive: true) throws.
    final blockedBase = '${tmp.path}/vault_blocked';
    File(blockedBase).writeAsBytesSync([0]);
    final store = VaultStore(baseDir: blockedBase);

    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
      'borrowers.db': [10, 20, 30],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)), store);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected staging failure'),
    );
    // Two-file commit: the library must be UNCHANGED when the vault could
    // not be staged (no "new library + old vault" split-brain).
    final books = await db.select(db.books).get();
    expect(books.single.bookUid, 'keep');
  });

  test('C1: a backup with no vault leaves the store uninitialized', () async {
    final store = vaultStore();
    final zip = archive({
      'manifest.json': utf8.encode(manifest()), // hasBackupBlob: false
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)), store);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isRight(), isTrue);
    expect(store.isInitialized(), isFalse);
    // Nothing to keep on a fresh device → integrity can be claimed.
    result.match((_) => fail('unreachable'), (s) {
      expect(s.existingVaultKept, isFalse);
      expect(s.isIntact, isTrue);
    });
  });

  // Decision Q2 (review 2026-09-03): an archive WITHOUT a vault restored onto
  // a device WITH one keeps the device vault, and the summary must say so
  // instead of claiming "all loans reference an existing book" — the kept
  // vault's loans were never checked (restore cannot open it).
  test('no-vault archive on a device with a vault: kept + flagged', () async {
    final store = vaultStore();
    File(store.dbPath).parent.createSync(recursive: true);
    File(store.dbPath).writeAsBytesSync([9, 9, 9]);
    store.writeBlob('existing.key.blob');
    final zip = archive({
      'manifest.json': utf8.encode(manifest()), // hasBackupBlob: false
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)), store);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    result.match((f) => fail('expected success, got $f'), (s) {
      expect(s.existingVaultKept, isTrue);
      expect(s.isIntact, isFalse, reason: 'integrity is UNKNOWN, not proven');
      expect(s.borrowersRestored, 0);
    });
    // The device vault is untouched, byte for byte.
    expect(store.isInitialized(), isTrue);
    expect(File(store.dbPath).readAsBytesSync(), [9, 9, 9]);
    expect(store.readBlob(), 'existing.key.blob');
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
