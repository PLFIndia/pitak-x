import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/infrastructure/periodical_mapper.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';
import 'generation_fixture.dart';

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
/// rollback regression (REVIEW_FINDINGS_2 S10). M02: opened on the BUILDER
/// generation's catalogue copy, where restore now does its writes.
class _FtsFailingDb extends AppDatabase {
  _FtsFailingDb(super.executor);

  @override
  Future<void> rebuildFts() async => throw StateError('fts rebuild boom');
}

/// Runs [after] once the builder catalogue is written: a hook to inject a
/// fault at the NEXT commit boundary (covers / vault) of an M02 restore.
class _AfterRebuildDb extends AppDatabase {
  _AfterRebuildDb(super.executor, this.after);
  final void Function() after;

  @override
  Future<void> rebuildFts() async {
    await super.rebuildFts();
    after();
  }
}

void main() {
  late Directory tmp;
  late GenerationFixture gen;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_test');
    // M02: restore snapshots the ACTIVE generation's catalogue file and
    // switches generations, so the pre-restore DB must be a real file.
    gen = GenerationFixture(tmp);
    db = gen.db;
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Rows of whichever generation is CURRENT after a restore.
  Future<List<CatalogueItem>> activeBooks() async {
    final active = gen.openActiveCatalogue();
    try {
      return (await active.select(active.books).get())
          .map((r) => r.toDomain())
          .toList();
    } finally {
      await active.close();
    }
  }

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

  String manifest({
    int schemaVersion = 1,
    bool hasBackupBlob = false,
    bool hasIdentity = false,
    bool hasNetwork = false,
    bool hasItemKinds = false,
    bool hasPeriodicals = false,
  }) => jsonEncode({
    'schemaVersion': schemaVersion,
    'exportedAt': 123,
    'hasBooks': true,
    'hasWishlist': true,
    'hasBorrowers': hasBackupBlob,
    'hasBackupBlob': hasBackupBlob,
    'hasCovers': false,
    if (hasIdentity) 'hasIdentity': true,
    if (hasNetwork) 'hasNetwork': true,
    if (hasItemKinds) 'hasItemKinds': true,
    if (hasPeriodicals) 'hasPeriodicals': true,
  });

  /// The pre-restore device vault store (inside the active generation).
  VaultStore vaultStore() => gen.store;

  /// Builds a legacy Room books.db with the given (id, uid, title) rows.
  /// `added_date` is fixed (NOT NULL column); everything else defaults.
  Uint8List buildBooksDbWith(List<({int id, String uid, String title})> rows) {
    final path = '${tmp.path}/src_books_${rows.length}_${rows.first.id}.db';
    final db = sqlite3.open(path)
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
    ''');
    for (final r in rows) {
      db.execute(
        'INSERT INTO books(id, book_uid, title, added_date) '
        'VALUES (?, ?, ?, 1000)',
        [r.id, r.uid, r.title],
      );
    }
    db.dispose();
    return File(path).readAsBytesSync();
  }

  RestoreBackup restorer(
    VaultRepository vault, [
    VaultStore? store,
    CatalogueOpener? openCatalogue,
  ]) => gen.restorer(
    vault: vault,
    guard: FakeReplacementGuard(
      failure: store?.isInitialized() ?? false
          ? const ValidationFailure('Unlock the borrowers vault first.')
          : null,
    ),
    openCatalogue: openCatalogue,
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

    final summary = result.getOrElse(
      (f) => fail('unexpected failure: ${f is StorageFailure ? f.reason : f}'),
    );
    expect(summary.booksRestored, 1);
    expect(summary.wishlistRestored, 1);
    expect(summary.isIntact, isTrue);

    // Preserved id + uid + Unicode title in the NEW active generation (M02:
    // restore switched generations; the pre-restore file is gone).
    expect(gen.switched, hasLength(1));
    final active = gen.openActiveCatalogue();
    addTearDown(active.close);
    final books = await active.select(active.books).get();
    expect(books.single.id, 7);
    expect(books.single.itemUid, 'uid-7');
    expect(books.single.title, 'गोदान');
    expect(books.single.copyCount, 2);

    final wishlist = await active.select(active.wishlistBooks).get();
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
    // Pre-restore device state: one existing book.
    await db
        .into(db.books)
        .insert(
          const CatalogueItem(title: 'PreExisting', addedDate: 1).toCompanion(),
        );

    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    // M02: the fault is injected into the BUILDER generation's catalogue.
    final r = restorer(
      _FakeVault(right(VaultData.empty)),
      null,
      (path) => _FtsFailingDb(NativeDatabase(File(path))),
    );
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<StorageFailure>());
    // Reported failure == device state: fully pre-restore, no switch.
    expect(gen.switched, isEmpty);
    expect(gen.current().name, gen.active.name);
    final books = await db.select(db.books).get();
    expect(books.map((b) => b.title), ['PreExisting']);
    final wishlist = await db.select(db.wishlistBooks).get();
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

    final active = gen.openActiveCatalogue();
    addTearDown(active.close);
    final hits = await active
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
            itemUid: const Value('old'),
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

    final books = await activeBooks();
    expect(books.length, 1);
    expect(books.single.itemUid, 'uid-7'); // OLD row gone
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
            itemUid: const Value('keep'),
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
    expect(books.single.itemUid, 'keep');
  });

  test('C1: persists the restored vault to the live VaultStore', () async {
    // The fake vault doesn't open the DB, so its exact bytes are opaque here;
    // we only assert they are installed at the live path verbatim (M02: the
    // live path is the NEW generation's vault dir after the switch).
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
    final r = restorer(vault);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isRight(), isTrue);
    // Before C1 this was false: the vault was read for counts then discarded.
    final store = gen.activeStore();
    expect(store.isInitialized(), isTrue);
    expect(File(store.dbPath).readAsBytesSync(), borrowersBytes);
    expect(store.readBlob(), blob);
  });

  test('vault install failure aborts the WHOLE restore (no switch)', () async {
    // Pre-restore library row that must survive a failed restore.
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: 'KEEP',
            addedDate: 1,
            itemUid: const Value('keep'),
          ),
        );
    // Sabotage the vault install: delete the staged borrowers.db copy right
    // after the catalogue was built, so installRestored's copySync throws.
    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
      'borrowers.db': [10, 20, 30],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });
    final r = restorer(
      _FakeVault(right(VaultData.empty)),
      null,
      (path) => _AfterRebuildDb(NativeDatabase(File(path)), () {
        File('${tmp.path}/restore_work/borrowers.db').deleteSync();
      }),
    );
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected vault install failure'),
    );
    // M02: one switch or none — the library must be UNCHANGED when the vault
    // could not be installed (no "new library + old vault" split-brain).
    expect(gen.switched, isEmpty);
    final books = await db.select(db.books).get();
    expect(books.single.itemUid, 'keep');
    expect(gen.store.isInitialized(), isFalse);
  });

  test('C1: a backup with no vault leaves the store uninitialized', () async {
    final zip = archive({
      'manifest.json': utf8.encode(manifest()), // hasBackupBlob: false
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)));
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isRight(), isTrue);
    expect(gen.activeStore().isInitialized(), isFalse);
    // Nothing to keep on a fresh device → integrity can be claimed.
    result.match((_) => fail('unreachable'), (s) {
      expect(s.existingVaultKept, isFalse);
      expect(s.isIntact, isTrue);
    });
  });

  // M03 policy C supersedes keep-and-warn: unknown loans require unlock,
  // and a colliding numeric ID must never substitute a different book.
  test('M03: no-vault restore refuses unchecked existing loan links', () async {
    final store = vaultStore();
    File(store.dbPath).parent.createSync(recursive: true);
    File(store.dbPath).writeAsBytesSync([9, 9, 9]);
    store.writeBlob('existing.key.blob');
    await db
        .into(db.books)
        .insert(
          const CatalogueItem(
            id: 7,
            itemUid: 'different-uid',
            title: 'Keep me',
          ).toCompanion(),
        );
    final zip = archive({
      'manifest.json': utf8.encode(manifest()), // hasBackupBlob: false
      'books.db': buildBooksDb(),
      'wishlist.db': buildWishlistDb(),
    });
    final r = restorer(_FakeVault(right(VaultData.empty)), store);
    final p = pass();
    final result = await r.restore(archiveBytes: zip, passphrase: p);
    p.dispose();

    expect(result.isLeft(), isTrue);
    expect((await db.select(db.books).get()).single.itemUid, 'different-uid');
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
            Loan(itemId: 999, borrowerId: 1, lentDate: 1), // book 999 missing
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

  group('N13 — inspect before restore', () {
    test('inspectArchive returns the manifest without restoring', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest()),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final inspected = await r.inspectArchive(zip);
      final m = inspected.getOrElse((f) => fail('unexpected: $f')).manifest;
      expect(m.hasBackupBlob, isFalse);
      expect(m.hasBooks, isTrue);
      expect(m.hasWishlist, isTrue);
      // Nothing was written: inspection must not touch the live DB.
      expect(await db.select(db.books).get(), isEmpty);
    });

    test('inspectArchive flags a vault-bearing archive', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'borrowers.db': [1, 2, 3],
        'backup_blob': utf8.encode('salt.iv.ct'),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final m = (await r.inspectArchive(
        zip,
      )).getOrElse((f) => fail('unexpected: $f')).manifest;
      expect(m.hasBackupBlob, isTrue);
    });

    test('inspectArchive rejects a corrupt archive', () async {
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final inspected = await r.inspectArchive(
        Uint8List.fromList([0, 1, 2, 3]),
      );
      inspected.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected corrupt'),
      );
    });

    test('inspectArchive refuses a too-new schema', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(schemaVersion: 99)),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final inspected = await r.inspectArchive(zip);
      inspected.match(
        (f) => expect(f, isA<SchemaTooNewFailure>()),
        (_) => fail('expected schema-too-new'),
      );
    });

    test('a vault-free archive restores with NO passphrase', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest()),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      // N13: a vault-free archive restores with NO passphrase argument.
      final result = await r.restore(archiveBytes: zip);
      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.booksRestored, 1);
      expect(summary.existingVaultKept, isFalse);
    });

    test('a vault-bearing archive with NO passphrase fails closed', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasBackupBlob: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'borrowers.db': [1, 2, 3],
        'backup_blob': utf8.encode('salt.iv.ct'),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final result = await r.restore(archiveBytes: zip);
      result.match(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected validation failure'),
      );
      // Fail closed BEFORE any device write.
      expect(await db.select(db.books).get(), isEmpty);
    });
  });

  group('§3.4 — identity.json / network.json entries', () {
    const validId = 'cccccccccccccccccccccccccccccccc';

    Uint8List networkJson(List<String> rows) =>
        utf8.encode('{"schemaVersion": 1, "libraries": [${rows.join(',')}]}');

    test('an archive WITHOUT the entries changes neither identity nor '
        'network (Kotlin-era)', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest()),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.restoredIdentity, isNull);
      expect(summary.restoredNetwork, isNull);
      expect(summary.identityInvalid, isFalse);
      expect(summary.networkInvalid, isFalse);
    });

    test('valid entries are parsed + validated into the summary', () async {
      final zip = archive({
        'manifest.json': utf8.encode(
          manifest(hasIdentity: true, hasNetwork: true),
        ),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'identity.json': utf8.encode(
          '{"libraryId": "$validId", "libraryName": "Meera Road"}',
        ),
        'network.json': networkJson([
          '{"siteUrl": "https://hub.github.io/x/", "name": "Hub", "id": 5, "membership": "confirmed"}',
        ]),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.restoredIdentity!.id, validId);
      expect(summary.restoredIdentity!.name, 'Meera Road');
      final network = summary.restoredNetwork!;
      expect(network.single.siteUrl, 'https://hub.github.io/x/');
      expect(network.single.membership, MembershipState.confirmed);
      expect(summary.identityInvalid, isFalse);
      expect(summary.networkInvalid, isFalse);
    });

    test('an invalid identity.json is not adopted but IS reported', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasIdentity: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'identity.json': utf8.encode('{"libraryId": "NOT-HEX"}'),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final result = await r.restore(archiveBytes: zip);
      // The catalogue restore itself is UNAFFECTED (additive extras never
      // roll it back); the summary carries the truth.
      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.booksRestored, 1);
      expect(summary.restoredIdentity, isNull);
      expect(summary.identityInvalid, isTrue);
    });

    test('an oversized identity.json never reaches the JSON parser (L2 byte '
        'cap) — not adopted, but reported', () async {
      // A valid identity padded past the 4 KiB budget with a huge name. The
      // zip extractor's per-entry cap (200 MiB, sized for covers) would
      // happily inflate this; the reader's budget refuses it BEFORE decoding
      // — fail closed like an invalid entry, exactly like the network cap.
      final oversized = utf8.encode(
        '{"libraryId": "$validId", "libraryName": "${'x' * (5 * 1024)}"}',
      );
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasIdentity: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'identity.json': oversized,
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.booksRestored, 1); // the catalogue restore is unaffected
      expect(summary.restoredIdentity, isNull);
      expect(summary.identityInvalid, isTrue);

      // Inspection (the restore page's peek) sees the same "unreadable".
      final inspected = (await r.inspectArchive(
        zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(inspected.manifest.hasIdentity, isTrue);
      expect(inspected.identity, isNull);
    });

    test(
      'one corrupt network row ⇒ the others restore, drop counted (§6)',
      () async {
        final zip = archive({
          'manifest.json': utf8.encode(manifest(hasNetwork: true)),
          'books.db': buildBooksDb(),
          'wishlist.db': buildWishlistDb(),
          'network.json': networkJson([
            '{"siteUrl": "https://good.github.io/x/", "name": "Good", "id": 1}',
            '{"siteUrl": "https://evil.example.com/", "id": 2}',
          ]),
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final summary = (await r.restore(
          archiveBytes: zip,
        )).getOrElse((f) => fail('unexpected: $f'));
        expect(summary.restoredNetwork, hasLength(1));
        expect(summary.restoredNetwork!.single.name, 'Good');
        expect(summary.networkRowsDropped, 1);
        expect(summary.networkInvalid, isFalse);
      },
    );

    test('duplicate network rows collapse first-wins (M9) — a duplicated '
        'siteUrl used to make the whole replaceAll fail on UNIQUE', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasNetwork: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'network.json': networkJson([
          '{"siteUrl": "https://dup.github.io/x/", "name": "First", "id": 1}',
          '{"siteUrl": "https://dup.github.io/x/", "name": "Second", "id": 2}',
          '{"siteUrl": "https://fine.github.io/y/", "name": "Fine", "id": 3}',
        ]),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.restoredNetwork!.map((row) => row.name), [
        'First',
        'Fine',
      ]);
      expect(summary.networkRowsDropped, 1);
      expect(summary.networkInvalid, isFalse);
    });

    test('an oversized network.json reads as unusable (M9 byte cap)', () async {
      // A valid row padded past the 4 MiB entry budget with a huge name.
      // The zip extractor's per-entry cap (200 MiB, sized for covers) would
      // happily inflate this; the codec budget refuses it BEFORE the JSON
      // parser sees it — fail closed like a corrupt envelope.
      final padded =
          '{"siteUrl": "https://big.github.io/x/", "name": "${'x' * (4 * 1024 * 1024)}"}';
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasNetwork: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'network.json': networkJson([padded]),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.restoredNetwork, isNull);
      expect(summary.networkInvalid, isTrue);
    });

    test('a flagged-but-unreadable network.json ⇒ networkInvalid', () async {
      final zip = archive({
        'manifest.json': utf8.encode(manifest(hasNetwork: true)),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
        'network.json': utf8.encode('{broken'),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(
        archiveBytes: zip,
      )).getOrElse((f) => fail('unexpected: $f'));
      expect(summary.restoredNetwork, isNull);
      expect(summary.networkInvalid, isTrue);
    });

    test(
      'inspectArchive surfaces the identity for the restore-page copy',
      () async {
        final zip = archive({
          'manifest.json': utf8.encode(manifest(hasIdentity: true)),
          'books.db': buildBooksDb(),
          'wishlist.db': buildWishlistDb(),
          'identity.json': utf8.encode(
            '{"libraryId": "$validId", "libraryName": "Meera Road"}',
          ),
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final inspected = (await r.inspectArchive(
          zip,
        )).getOrElse((f) => fail('unexpected: $f'));
        expect(inspected.manifest.hasIdentity, isTrue);
        expect(inspected.identity!.name, 'Meera Road');
        expect(inspected.identity!.id, validId);
      },
    );

    test(
      'inspectArchive yields a null identity when the entry is invalid',
      () async {
        final zip = archive({
          'manifest.json': utf8.encode(manifest(hasIdentity: true)),
          'books.db': buildBooksDb(),
          'wishlist.db': buildWishlistDb(),
          'identity.json': utf8.encode('{"libraryId": "NOPE"}'),
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final inspected = (await r.inspectArchive(
          zip,
        )).getOrElse((f) => fail('unexpected: $f'));
        // Flag true (the page says "unreadable"), identity null.
        expect(inspected.manifest.hasIdentity, isTrue);
        expect(inspected.identity, isNull);
      },
    );
  });

  // ADR 0014 W2: kinds are explicit in item_kinds.json; series + issue
  // details ride in periodicals.json. Literal JSON pins the wire contract.
  group('W2 — item kinds + periodicals (ADR 0014)', () {
    const kindsJson = '''
      { "schemaVersion": 1,
        "kinds": [ { "bookUid": "uid-8", "kind": "magazine-issue" },
                   { "bookUid": "uid-9", "kind": "other" } ] }''';
    const periodicalsJson = '''
      { "schemaVersion": 1,
        "periodicals": [ { "periodicalUid": "puid-1", "title": "Chandamama",
                           "issn": "0577-6058", "frequency": "monthly" } ],
        "issues": [ { "bookUid": "uid-8", "periodicalUid": "puid-1",
                      "volume": 249, "issueNumber": 10,
                      "issueDate": 1759276800000 } ] }''';

    Uint8List threeRows() => buildBooksDbWith(const [
      (id: 7, uid: 'uid-7', title: 'गोदान'),
      (id: 8, uid: 'uid-8', title: 'Chandamama — Vol 249 No 10 (Oct 2026)'),
      (id: 9, uid: 'uid-9', title: 'Carrom board'),
    ]);

    test(
      'kinds, issue details and periodicals land in the new generation',
      () async {
        final zip = archive({
          'manifest.json': utf8.encode(
            manifest(hasItemKinds: true, hasPeriodicals: true),
          ),
          'books.db': threeRows(),
          'wishlist.db': buildWishlistDb(),
          'item_kinds.json': utf8.encode(kindsJson),
          'periodicals.json': utf8.encode(periodicalsJson),
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final summary = (await r.restore(archiveBytes: zip)).getOrElse(
          (f) => fail('unexpected: ${f is StorageFailure ? f.reason : f}'),
        );
        expect(summary.kindsApplied, 2);
        expect(summary.issuesLinked, 1);
        expect(summary.issuesDetached, 0);
        expect(summary.periodicalsRestored, 1);
        expect(summary.rowsSkippedUnknownKind, 0);
        expect(summary.itemKindsInvalid, isFalse);
        expect(summary.periodicalsInvalid, isFalse);

        final active = gen.openActiveCatalogue();
        addTearDown(active.close);
        final books = await active.select(active.books).get();
        expect(
          {for (final b in books) b.itemUid: b.kind},
          {'uid-7': 'book', 'uid-8': 'magazine-issue', 'uid-9': 'other'},
        );
        final issues = await active.select(active.magazineIssues).get();
        expect(issues.single.itemId, 8);
        expect(issues.single.periodicalUid, 'puid-1');
        expect(issues.single.volume, 249);
        expect(issues.single.issueNumber, 10);
        expect(issues.single.issueDate, 1759276800000);
        final titles = await active.select(active.periodicals).get();
        expect(titles.single.periodicalUid, 'puid-1');
        expect(titles.single.title, 'Chandamama');
        expect(titles.single.issn, '0577-6058');
      },
    );

    test('a flag-less archive restores exactly as before — and the kind '
        'tables do NOT survive it', () async {
      // Pre-restore device state: a series with one issue (v5 tables).
      await db
          .into(db.periodicals)
          .insert(
            const Periodical(
              title: 'Stale title',
              periodicalUid: 'puid-stale',
            ).toCompanion(),
          );
      final staleId = await db
          .into(db.books)
          .insert(
            const CatalogueItem(
              title: 'Stale issue',
              addedDate: 1,
              itemUid: 'uid-stale',
            ).toCompanion(),
          );
      await DriftItemDetails(db).write(
        staleId,
        const IssueOf(periodicalUid: 'puid-stale', issueNumber: 1),
      );

      final zip = archive({
        'manifest.json': utf8.encode(manifest()),
        'books.db': buildBooksDb(),
        'wishlist.db': buildWishlistDb(),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(archiveBytes: zip)).getOrElse(
        (f) => fail('unexpected: ${f is StorageFailure ? f.reason : f}'),
      );
      // Books/wishlist behave exactly as before S21…
      expect(summary.booksRestored, 1);
      expect(summary.wishlistRestored, 1);
      expect(summary.kindsApplied, 0);
      expect(summary.periodicalsRestored, 0);
      expect(summary.itemKindsInvalid, isFalse);
      expect(summary.periodicalsInvalid, isFalse);

      // …and the authoritative overwrite covers the v5 tables too: a
      // flag-less archive carries no kinds, so no stale series/detail rows
      // may linger next to a catalogue of plain books (M02: no mixed state).
      final active = gen.openActiveCatalogue();
      addTearDown(active.close);
      expect(await active.select(active.periodicals).get(), isEmpty);
      expect(await active.select(active.magazineIssues).get(), isEmpty);
      final books = await active.select(active.books).get();
      expect(books.single.kind, 'book');
    });

    test('unhonoured links restore as books and are counted (§5.5)', () async {
      final zip = archive({
        'manifest.json': utf8.encode(
          manifest(hasItemKinds: true, hasPeriodicals: true),
        ),
        'books.db': threeRows(),
        'wishlist.db': buildWishlistDb(),
        'item_kinds.json': utf8.encode('''
          { "schemaVersion": 1,
            "kinds": [ { "bookUid": "uid-8", "kind": "magazine-issue" },
                       { "bookUid": "uid-9", "kind": "hologram" } ] }'''),
        'periodicals.json': utf8.encode('''
          { "schemaVersion": 1,
            "periodicals": [ { "periodicalUid": "puid-1",
                               "title": "Chandamama" } ],
            "issues": [ { "bookUid": "uid-gone", "periodicalUid": "puid-1",
                          "issueNumber": 4 } ] }'''),
      });
      final r = restorer(_FakeVault(right(VaultData.empty)));
      final summary = (await r.restore(archiveBytes: zip)).getOrElse(
        (f) => fail('unexpected: ${f is StorageFailure ? f.reason : f}'),
      );
      // uid-8: declared an issue but no issues[] entry → detached.
      // uid-gone: an issues[] entry for a row books.db does not have →
      // detached. uid-9: unknown kind token → skipped.
      expect(summary.issuesDetached, 2);
      expect(summary.rowsSkippedUnknownKind, 1);
      expect(summary.kindsApplied, 0);
      expect(summary.periodicalsRestored, 1);

      final active = gen.openActiveCatalogue();
      addTearDown(active.close);
      final books = await active.select(active.books).get();
      expect(
        books.map((b) => b.kind).toSet(),
        {'book'},
        reason: 'every detached/skipped row restores as a plain book',
      );
      expect(await active.select(active.magazineIssues).get(), isEmpty);
      expect(await active.select(active.periodicals).get(), hasLength(1));
    });

    test(
      'flagged-but-missing entries flag invalid; rows restore as books',
      () async {
        final zip = archive({
          'manifest.json': utf8.encode(
            manifest(hasItemKinds: true, hasPeriodicals: true),
          ),
          'books.db': threeRows(),
          'wishlist.db': buildWishlistDb(),
          // Both entries ABSENT despite the flags (a truncated archive).
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final summary = (await r.restore(archiveBytes: zip)).getOrElse(
          (f) => fail('unexpected: ${f is StorageFailure ? f.reason : f}'),
        );
        expect(summary.itemKindsInvalid, isTrue);
        expect(summary.periodicalsInvalid, isTrue);
        expect(summary.kindsApplied, 0);
        expect(summary.periodicalsRestored, 0);

        final active = gen.openActiveCatalogue();
        addTearDown(active.close);
        final books = await active.select(active.books).get();
        expect(books.map((b) => b.kind).toSet(), {'book'});
        expect(await active.select(active.periodicals).get(), isEmpty);
      },
    );

    test(
      'duplicate issue identity keys refuse the archive (fail closed)',
      () async {
        // Only a crafted file can carry two issues with the same D6 key (the
        // writer's source table enforces the UNIQUE index): restore refuses
        // rather than pick one — the M15 authoritative-overwrite rule.
        final zip = archive({
          'manifest.json': utf8.encode(
            manifest(hasItemKinds: true, hasPeriodicals: true),
          ),
          'books.db': buildBooksDbWith(const [
            (id: 8, uid: 'uid-8', title: 'Issue A'),
            (id: 12, uid: 'uid-12', title: 'Issue A (dup)'),
          ]),
          'wishlist.db': buildWishlistDb(),
          'item_kinds.json': utf8.encode(
            '''
          { "schemaVersion": 1,
            "kinds": [ { "bookUid": "uid-8", "kind": "magazine-issue" },
                       { "bookUid": "uid-12", "kind": "magazine-issue" } ] }''',
          ),
          'periodicals.json': utf8.encode('''
          { "schemaVersion": 1,
            "periodicals": [ { "periodicalUid": "puid-1",
                               "title": "Chandamama" } ],
            "issues": [ { "bookUid": "uid-8", "periodicalUid": "puid-1",
                          "volume": 249, "issueNumber": 10 },
                        { "bookUid": "uid-12", "periodicalUid": "puid-1",
                          "volume": 249, "issueNumber": 10 } ] }'''),
        });
        final r = restorer(_FakeVault(right(VaultData.empty)));
        final result = await r.restore(archiveBytes: zip);
        expect(result.getLeft().toNullable(), isA<StorageFailure>());
        // Nothing switched: the pre-restore device state is byte-identical.
        expect(gen.switched, isEmpty);
        expect(await db.select(db.books).get(), isEmpty);
      },
    );
  });
}
