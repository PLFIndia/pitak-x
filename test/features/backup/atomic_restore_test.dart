import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';

/// M02 (astra-review.md): a restore must switch catalogue, vault and covers as
/// ONE unit. Every test here injects a fault at one commit boundary and asserts
/// the device is left EXACTLY on its pre-restore generation — or, after a
/// successful switch, entirely on the new one.
///
/// The restorer under test works on real files: the active generation is a
/// directory with a real SQLite catalogue, vault files and covers; the
/// candidate generation is built next to it; the switch is the CURRENT rename.
class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  _FakeVault(this._result);
  final Either<Failure, VaultData> _result;
  int reads = 0;
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    reads++;
    return _result;
  }
}

/// Lets a test break the new generation's catalogue at a chosen moment.
class _FaultyCatalogueFactory {
  Future<void> Function()? afterRebuild;
  bool failRebuild = false;

  AppDatabase open(String path) => _FaultyDb(this, NativeDatabase(File(path)));
}

class _FaultyDb extends AppDatabase {
  _FaultyDb(this._factory, super.executor);
  final _FaultyCatalogueFactory _factory;

  @override
  Future<void> rebuildFts() async {
    if (_factory.failRebuild) throw StateError('synthetic FTS failure');
    await super.rebuildFts();
    await _factory.afterRebuild?.call();
  }
}

void main() {
  late Directory docs;
  late DataGenerations generations;
  late DataGeneration active;
  late AppDatabase live;
  late VaultStore liveStore;
  late _FaultyCatalogueFactory catalogues;
  final switched = <DataGeneration>[];

  setUp(() {
    docs = Directory.systemTemp.createTempSync('atomic_restore_test');
    generations = DataGenerations(docsDir: docs.path);
    active = generations.open();
    live = AppDatabase(NativeDatabase(File(active.catalogueDbPath)));
    liveStore = VaultStore(baseDir: active.vaultDir);
    catalogues = _FaultyCatalogueFactory();
    switched.clear();
  });

  tearDown(() async {
    await live.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  SecretBytes pass() => SecretBytes(Uint8List.fromList([1, 2, 3]));

  /// The restorer wired the way DI wires it, except that the generation
  /// switch is observed here (the provider's `activate` does the same thing
  /// through `DataGenerations.activate`).
  RestoreBackup restorer({
    VaultRepository? vault,
    CatalogueReplacementGuard? guard,
    Future<DataGeneration> Function(DataGeneration)? activate,
  }) => RestoreBackup(
    vault: vault ?? _FakeVault(right(VaultData.empty)),
    generations: generations,
    activeGeneration: () async => active,
    activate:
        activate ??
        (generation) async {
          final now = generations.activate(generation);
          switched.add(now);
          return now;
        },
    openCatalogue: catalogues.open,
    workDir: p.join(docs.path, 'restore_work'),
    replacementGuard: guard ?? FakeReplacementGuard(),
  );

  // --- archive fixtures ---------------------------------------------------

  Uint8List booksDb({int id = 7, String uid = 'uid-7', String? cover}) {
    final path = p.join(docs.path, 'src_books_$id.db');
    if (File(path).existsSync()) File(path).deleteSync();
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
      ..execute(
        'INSERT INTO books(id,book_uid,title,cover_url,added_date) '
        'VALUES (?, ?, ?, ?, 1)',
        [id, uid, 'Restored', cover],
      )
      ..dispose();
    return File(path).readAsBytesSync();
  }

  Uint8List wishlistDb() {
    final path = p.join(docs.path, 'src_wishlist.db');
    if (File(path).existsSync()) File(path).deleteSync();
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
      ..execute(
        'INSERT INTO wishlist_books(id,title,priority,source,added_date) '
        "VALUES (3,'Wanted',2,'SCANNED',500)",
      )
      ..dispose();
    return File(path).readAsBytesSync();
  }

  Uint8List zip(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((k, v) => a.addFile(ArchiveFile(k, v.length, v)));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  }

  List<int> manifest({bool vault = false, bool covers = false}) => utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'exportedAt': 123,
      'hasBooks': true,
      'hasWishlist': true,
      'hasBorrowers': vault,
      'hasBackupBlob': vault,
      'hasCovers': covers,
    }),
  );

  Uint8List vaultFreeArchive({bool covers = false, String? coverRef}) => zip({
    'manifest.json': manifest(covers: covers),
    'books.db': booksDb(cover: coverRef),
    'wishlist.db': wishlistDb(),
    if (covers) 'cover_new.jpg': [8, 8, 8],
  });

  Uint8List vaultArchive() => zip({
    'manifest.json': manifest(vault: true),
    'books.db': booksDb(),
    'wishlist.db': wishlistDb(),
    'borrowers.db': [10, 20, 30],
    'backup_blob': utf8.encode('new.key.blob'),
  });

  // --- pre-restore device state -------------------------------------------

  Future<void> seedDevice({bool withVault = false}) async {
    await live
        .into(live.books)
        .insert(
          BooksCompanion.insert(
            title: 'PreExisting',
            addedDate: 1,
            bookUid: const Value('keep'),
            coverUrl: const Value('covers/old.jpg'),
          ),
        );
    Directory(active.coversDir).createSync(recursive: true);
    File(p.join(active.coversDir, 'old.jpg')).writeAsBytesSync([9, 9, 9]);
    if (withVault) {
      File(liveStore.dbPath).writeAsBytesSync([1, 2, 3]);
      liveStore
        ..writeBlob('old.key.blob')
        ..writeBioBlob('old.bio.blob');
    }
  }

  /// Asserts the device is byte-for-byte on the pre-restore generation: same
  /// pointer, same directory, catalogue/covers/vault untouched, no leftovers.
  Future<void> expectUnchanged({bool withVault = false}) async {
    expect(generations.open().name, active.name);
    expect(switched, isEmpty);
    final rows = await live.select(live.books).get();
    expect(rows.single.bookUid, 'keep');
    expect(await live.select(live.wishlistBooks).get(), isEmpty);
    expect(File(p.join(active.coversDir, 'old.jpg')).readAsBytesSync(), [
      9,
      9,
      9,
    ]);
    if (withVault) {
      expect(File(liveStore.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect(liveStore.readBlob(), 'old.key.blob');
      expect(liveStore.readBioBlob(), 'old.bio.blob');
    } else {
      expect(liveStore.isInitialized(), isFalse);
    }
    // No builder directory survives a failure (privacy: no second copy).
    final dirs = Directory(
      p.join(docs.path, 'data'),
    ).listSync().whereType<Directory>().map((d) => p.basename(d.path)).toList();
    expect(dirs, [active.name]);
    expect(Directory(p.join(docs.path, 'restore_work')).existsSync(), isFalse);
  }

  group('success: everything moves together', () {
    test('a vault-free restore lands catalogue + covers in a NEW generation '
        'and the old generation is gone', () async {
      await seedDevice();
      final result = await restorer().restore(
        archiveBytes: vaultFreeArchive(
          covers: true,
          coverRef: 'covers/new.jpg',
        ),
      );

      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.booksRestored, 1);
      expect(summary.wishlistRestored, 1);
      expect(switched.single.name, isNot(active.name));
      final now = generations.open();
      expect(now.name, switched.single.name);
      expect(Directory(active.path).existsSync(), isFalse);
      // The new generation's catalogue has ONLY the restored rows and FTS.
      final db = AppDatabase(NativeDatabase(File(now.catalogueDbPath)));
      addTearDown(db.close);
      final rows = await db.select(db.books).get();
      expect(rows.single.id, 7);
      expect(rows.single.bookUid, 'uid-7');
      expect((await db.select(db.wishlistBooks).get()).single.id, 3);
      final hits = await db
          .customSelect(
            'SELECT rowid FROM books_fts WHERE books_fts MATCH ?1',
            variables: [const Variable<String>('"Restored"')],
          )
          .get();
      expect(hits.single.read<int>('rowid'), 7);
      // Covers: only the archive's, the old one did not leak across.
      expect(File(p.join(now.coversDir, 'new.jpg')).readAsBytesSync(), [
        8,
        8,
        8,
      ]);
      expect(File(p.join(now.coversDir, 'old.jpg')).existsSync(), isFalse);
      expect(
        Directory(p.join(docs.path, 'restore_work')).existsSync(),
        isFalse,
      );
    });

    test('a vault-bearing restore installs the archive vault pair in the new '
        'generation and drops the old biometric blob', () async {
      await seedDevice(withVault: true);
      final vault = _FakeVault(
        right(
          const VaultData(
            borrowers: [Borrower(id: 1, name: 'Asha')],
            loans: [],
          ),
        ),
      );
      final p1 = pass();
      final result = await restorer(
        vault: vault,
      ).restore(archiveBytes: vaultArchive(), passphrase: p1);
      p1.dispose();

      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.borrowersRestored, 1);
      final now = generations.open();
      expect(now.name, switched.single.name);
      final store = VaultStore(baseDir: now.vaultDir);
      expect(store.isInitialized(), isTrue);
      expect(File(store.dbPath).readAsBytesSync(), [10, 20, 30]);
      expect(store.readBlob(), 'new.key.blob');
      // The old biometric blob wrapped the OLD key: it must not carry over.
      expect(store.hasBioBlob(), isFalse);
    });

    test('a vault-free restore on a device WITH a vault carries the vault '
        'pair AND biometric blob into the new generation unchanged', () async {
      await seedDevice(withVault: true);
      final result = await restorer(
        guard: FakeReplacementGuard(loanIds: {}),
      ).restore(archiveBytes: vaultFreeArchive());

      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.existingVaultKept, isTrue);
      final now = generations.open();
      final store = VaultStore(baseDir: now.vaultDir);
      expect(File(store.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect(store.readBlob(), 'old.key.blob');
      expect(store.readBioBlob(), 'old.bio.blob');
    });

    test('an archive without covers keeps the device covers (they may still '
        'be referenced by restored rows)', () async {
      await seedDevice();
      final result = await restorer().restore(
        archiveBytes: vaultFreeArchive(coverRef: 'covers/old.jpg'),
      );

      expect(result.isRight(), isTrue);
      final now = generations.open();
      expect(File(p.join(now.coversDir, 'old.jpg')).readAsBytesSync(), [
        9,
        9,
        9,
      ]);
    });

    test('two restores in one session chain generations', () async {
      await seedDevice();
      final r = restorer();
      expect(
        (await r.restore(archiveBytes: vaultFreeArchive())).isRight(),
        isTrue,
      );
      active = switched.last; // as the provider would republish
      expect(
        (await r.restore(archiveBytes: vaultFreeArchive())).isRight(),
        isTrue,
      );
      expect(switched.map((g) => g.name).toList(), [
        'gen-000002',
        'gen-000003',
      ]);
      expect(generations.open().name, 'gen-000003');
    });
  });

  group('fault injection: the device stays on the OLD generation', () {
    test('wrong passphrase (vault unlock fails)', () async {
      await seedDevice(withVault: true);
      final p1 = pass();
      final result = await restorer(
        vault: _FakeVault(left(const WrongPassphraseFailure())),
      ).restore(archiveBytes: vaultArchive(), passphrase: p1);
      p1.dispose();

      expect(result.getLeft().toNullable(), isA<WrongPassphraseFailure>());
      await expectUnchanged(withVault: true);
    });

    test('catalogue plan refusal (guard) — nothing built', () async {
      await seedDevice(withVault: true);
      final result = await restorer(
        guard: FakeReplacementGuard(
          failure: const ValidationFailure('Unlock the vault first.'),
        ),
      ).restore(archiveBytes: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      await expectUnchanged(withVault: true);
    });

    test('FTS rebuild failure inside the new catalogue', () async {
      await seedDevice();
      catalogues.failRebuild = true;
      final result = await restorer().restore(archiveBytes: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test(
      'lease lost after the catalogue was written but before the switch',
      () async {
        await seedDevice();
        final guard = FakeReplacementGuard();
        catalogues.afterRebuild = () async => guard.current = false;
        final result = await restorer(
          guard: guard,
        ).restore(archiveBytes: vaultFreeArchive());

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        await expectUnchanged();
      },
    );

    test('corrupt legacy books.db', () async {
      await seedDevice();
      final result = await restorer().restore(
        archiveBytes: zip({
          'manifest.json': manifest(),
          'books.db': [0, 1, 2, 3],
          'wishlist.db': wishlistDb(),
        }),
      );

      expect(result.getLeft().toNullable(), isA<BackupCorruptFailure>());
      await expectUnchanged();
    });

    test('a cover that cannot be written fails closed (no best-effort partial '
        'cover set, no switch)', () async {
      await seedDevice();
      // Fault at the cover stage, AFTER the catalogue copy succeeded: put a
      // FILE where the builder's covers directory must be created.
      catalogues.afterRebuild = () async {
        File(
          p.join(docs.path, 'data', 'gen-000002', 'covers'),
        ).writeAsBytesSync([0]);
      };
      final result = await restorer(
        activate: (g) async => fail('must not switch'),
      ).restore(archiveBytes: vaultFreeArchive(covers: true));

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test('the pointer switch itself fails', () async {
      await seedDevice();
      final result = await restorer(
        activate: (g) async => throw const FileSystemException('disk full'),
      ).restore(archiveBytes: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test('vault-bearing archive missing borrowers.db', () async {
      await seedDevice(withVault: true);
      final p1 = pass();
      final result = await restorer().restore(
        archiveBytes: zip({
          'manifest.json': manifest(vault: true),
          'books.db': booksDb(),
          'wishlist.db': wishlistDb(),
          'backup_blob': utf8.encode('new.key.blob'),
        }),
        passphrase: p1,
      );
      p1.dispose();

      expect(result.getLeft().toNullable(), isA<BackupCorruptFailure>());
      await expectUnchanged(withVault: true);
    });
  });

  group('crash simulation: startup recovery', () {
    test('a fully built but never-switched generation is discarded at the '
        'next open and the old data is still active', () async {
      await seedDevice();
      // Build everything, then "crash" before the pointer rename.
      final result = await restorer(
        activate: (g) async => throw StateError('simulated crash'),
      ).restore(archiveBytes: vaultFreeArchive());
      expect(result.isLeft(), isTrue);
      // Even if discard had not run (a real crash), open() cleans up:
      final leftover = generations.beginNext(active);
      File(leftover.catalogueDbPath).writeAsBytesSync([1]);
      generations.complete(leftover);

      final reopened = DataGenerations(docsDir: docs.path).open();

      expect(reopened.name, active.name);
      expect(Directory(leftover.path).existsSync(), isFalse);
      await expectUnchanged();
    });
  });
}
