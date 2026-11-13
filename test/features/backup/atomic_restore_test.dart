import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/backup/infrastructure/restore_catalogue_builder.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../import_export/hostile_zip_builder.dart';
import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';

/// Review finding M02: a restore must switch catalogue, vault and covers as
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

/// What the lock-holding isolate is told. Plain data only, as for every
/// worker: a database handle cannot cross to another isolate.
typedef _WriteLockJob = ({String dbPath, SendPort events, int holdMs});

/// Runs in an isolate of its own and plays "the app is committing a write to
/// the catalogue right now": takes SQLite's exclusive lock on the file, says
/// so, and lets go when it is told to or when `holdMs` milliseconds have
/// passed, whichever comes first.
Future<void> _holdWriteLock(_WriteLockJob job) async {
  final release = ReceivePort();
  final db = sqlite3.open(job.dbPath);
  try {
    db.execute('BEGIN EXCLUSIVE');
    // "The lock is held", together with the way to end it early.
    job.events.send(release.sendPort);
    await release.first.timeout(
      Duration(milliseconds: job.holdMs),
      onTimeout: () => null,
    );
    db.execute('ROLLBACK');
  } finally {
    release.close();
    db.dispose();
  }
}

/// A write lock on a catalogue file, held by ANOTHER isolate.
///
/// Why another isolate (beginner note): SQLite's busy wait blocks the thread
/// that waits. A lock held by the test's own isolate could never be let go
/// while the restore waits for it, so the test would only ever see the wait
/// run out.
final class _HeldWriteLock {
  _HeldWriteLock._(this._release, this.gone);

  final SendPort _release;

  /// Completes when the lock is gone (the other isolate has ended).
  final Future<void> gone;

  /// Lets go now, without waiting for the time to run out.
  void release() => _release.send(null);

  /// Takes the lock on [dbPath] and answers once it IS held. It is let go
  /// after [atMost] at the latest, so a test that dies leaves no lock.
  static Future<_HeldWriteLock> take(
    String dbPath, {
    required Duration atMost,
  }) async {
    final events = ReceivePort();
    final next = StreamIterator<Object?>(events);
    await Isolate.spawn(
      _holdWriteLock,
      (dbPath: dbPath, events: events.sendPort, holdMs: atMost.inMilliseconds),
      // The isolate's last word, however it ends.
      onExit: events.sendPort,
    );
    await next.moveNext();
    final release = next.current;
    if (release is! SendPort) {
      events.close();
      fail('the other isolate ended without taking the lock');
    }
    Future<void> gone() async {
      await next.moveNext();
      events.close();
    }

    return _HeldWriteLock._(release, gone());
  }
}

void main() {
  late Directory docs;
  late DataGenerations generations;
  late DataGeneration active;
  late AppDatabase live;
  late VaultStore liveStore;
  late _FaultyCatalogueFactory catalogues;
  late RunFolders workFolders;
  final switched = <DataGeneration>[];

  /// Where a restore stages its databases (BR6): one `run-…` folder per
  /// restore, gone again on every way out.
  String workRoot() => p.join(docs.path, 'tmp', 'restore_work');

  /// The run folders that exist right now.
  List<String> runFolders() {
    final root = Directory(workRoot());
    if (!root.existsSync()) return const [];
    return [for (final entity in root.listSync()) p.basename(entity.path)];
  }

  setUp(() {
    docs = Directory.systemTemp.createTempSync('atomic_restore_test');
    generations = DataGenerations(docsDir: docs.path);
    active = generations.open();
    live = AppDatabase(NativeDatabase(File(active.catalogueDbPath)));
    liveStore = VaultStore(baseDir: active.vaultDir);
    catalogues = _FaultyCatalogueFactory();
    workFolders = RunFolders(rootPath: workRoot(), prefix: 'run');
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
    LegacyDbOpener? openLegacyDb,
    ActiveGenerationResolver? activeGeneration,
  }) => RestoreBackup(
    vault: vault ?? _FakeVault(right(VaultData.empty)),
    generations: generations,
    activeGeneration: activeGeneration ?? () async => active,
    activate:
        activate ??
        (generation) async {
          final now = generations.activate(generation);
          switched.add(now);
          return now;
        },
    openCatalogue: catalogues.open,
    openLegacyDb:
        openLegacyDb ?? (path) => sqlite3.open(path, mode: OpenMode.readOnly),
    workFolders: workFolders,
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

  var archives = 0;

  /// Writes [bytes] as a backup FILE and returns its path. BR6: a restore
  /// reads the backup from a file, the private copy the app's picker made.
  String file(List<int> bytes) {
    final folder = Directory(p.join(docs.path, 'tmp', 'chosen'))
      ..createSync(recursive: true);
    final path = p.join(folder.path, 'archive-${archives++}');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// A backup file with [entries], packed as an honest writer packs them.
  String zip(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((k, v) => a.addFile(ArchiveFile(k, v.length, v)));
    return file(ZipEncoder().encode(a));
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

  String vaultFreeArchive({bool covers = false, String? coverRef}) => zip({
    'manifest.json': manifest(covers: covers),
    'books.db': booksDb(cover: coverRef),
    'wishlist.db': wishlistDb(),
    if (covers) 'cover_new.jpg': [8, 8, 8],
  });

  String vaultArchive() => zip({
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
            itemUid: const Value('keep'),
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
    expect(rows.single.itemUid, 'keep');
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
    expect(runFolders(), isEmpty, reason: 'no run folder is left');
  }

  group('success: everything moves together', () {
    test('a vault-free restore lands catalogue + covers in a NEW generation '
        'and the old generation is gone', () async {
      await seedDevice();
      final result = await restorer().restore(
        archivePath: vaultFreeArchive(covers: true, coverRef: 'covers/new.jpg'),
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
      expect(rows.single.itemUid, 'uid-7');
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
      expect(runFolders(), isEmpty, reason: 'no run folder is left');
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
      ).restore(archivePath: vaultArchive(), passphrase: p1);
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
      ).restore(archivePath: vaultFreeArchive());

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
        archivePath: vaultFreeArchive(coverRef: 'covers/old.jpg'),
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
        (await r.restore(archivePath: vaultFreeArchive())).isRight(),
        isTrue,
      );
      active = switched.last; // as the provider would republish
      expect(
        (await r.restore(archivePath: vaultFreeArchive())).isRight(),
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
      ).restore(archivePath: vaultArchive(), passphrase: p1);
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
      ).restore(archivePath: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      await expectUnchanged(withVault: true);
    });

    test('FTS rebuild failure inside the new catalogue', () async {
      await seedDevice();
      catalogues.failRebuild = true;
      final result = await restorer().restore(archivePath: vaultFreeArchive());

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
        ).restore(archivePath: vaultFreeArchive());

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        await expectUnchanged();
      },
    );

    test('corrupt legacy books.db', () async {
      await seedDevice();
      final result = await restorer().restore(
        archivePath: zip({
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
      ).restore(archivePath: vaultFreeArchive(covers: true));

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test('the pointer switch itself fails', () async {
      await seedDevice();
      final result = await restorer(
        activate: (g) async => throw const FileSystemException('disk full'),
      ).restore(archivePath: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test('vault-bearing archive missing borrowers.db', () async {
      await seedDevice(withVault: true);
      final p1 = pass();
      final result = await restorer().restore(
        archivePath: zip({
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

  // BR6: the backup is read from a file by two workers, with the catalogue
  // work in between. Each fault here hits one of the new seams.
  group('BR6 — fault injection in the streamed restore', () {
    /// A backup FILE written by hand, so an entry can lie.
    String hostileFile(List<HostileEntry> entries) =>
        file(buildHostileZip(entries));

    /// The generation folders on disk, as the failed restore left them.
    /// Looked at BEFORE `expectUnchanged`, whose first step opens the
    /// generations the way an app start does and would tidy up itself.
    List<String> generationFolders() => Directory(
      p.join(docs.path, 'data'),
    ).listSync().whereType<Directory>().map((d) => p.basename(d.path)).toList();

    List<HostileEntry> honestParts({bool covers = true}) => [
      HostileEntry('manifest.json', manifest(covers: covers)),
      HostileEntry('books.db', booksDb()),
      HostileEntry('wishlist.db', wishlistDb()),
    ];

    test('a bad checksum on the LAST cover: nothing is switched, and the '
        'file itself is untouched', () async {
      await seedDevice();
      final archive = hostileFile([
        ...honestParts(),
        HostileEntry('cover_first.jpg', const [1, 2, 3]),
        HostileEntry('cover_second.jpg', const [4, 5, 6]),
        HostileEntry('cover_last.jpg', const [
          7,
          8,
          9,
        ], declaredCrc32: 0x12345678),
      ]);
      final before = File(archive).readAsBytesSync();

      final result = await restorer(
        activate: (g) async => fail('must not switch'),
      ).restore(archivePath: archive);

      expect(result.getLeft().toNullable(), isA<BackupCorruptFailure>());
      expect(generationFolders(), [active.name], reason: 'no builder left');
      await expectUnchanged();
      expect(File(archive).readAsBytesSync(), before);
    });

    test('a cover whose file is already in the new folder is never '
        'replaced: the restore fails closed', () async {
      await seedDevice();
      // After the catalogue copy, before the covers step: something put a
      // file where a cover is about to be written.
      catalogues.afterRebuild = () async {
        final covers = Directory(
          p.join(docs.path, 'data', 'gen-000002', 'covers'),
        )..createSync(recursive: true);
        File(p.join(covers.path, 'new.jpg')).writeAsBytesSync([0]);
      };

      final result = await restorer(
        activate: (g) async => fail('must not switch'),
      ).restore(archivePath: vaultFreeArchive(covers: true));

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(generationFolders(), [active.name], reason: 'no builder left');
      await expectUnchanged();
    });

    test(
      'the file is replaced by another backup between the two looks: '
      'the covers no longer fit the first look, nothing is switched',
      () async {
        await seedDevice();
        final archive = vaultFreeArchive(covers: true);
        // A different, perfectly valid backup: one cover more.
        final other = File(
          zip({
            'manifest.json': manifest(covers: true),
            'books.db': booksDb(id: 8, uid: 'uid-8'),
            'wishlist.db': wishlistDb(),
            'cover_new.jpg': [8, 8, 8],
            'cover_extra.jpg': [9, 9, 9],
          }),
        ).readAsBytesSync();
        var swapped = false;

        final result = await restorer(
          activate: (g) async => fail('must not switch'),
          // The databases are read between the first look and the covers.
          openLegacyDb: (path) {
            if (!swapped) {
              swapped = true;
              File(archive).writeAsBytesSync(other);
            }
            return sqlite3.open(path, mode: OpenMode.readOnly);
          },
        ).restore(archivePath: archive);

        expect(swapped, isTrue);
        expect(result.getLeft().toNullable(), isA<BackupCorruptFailure>());
        expect(generationFolders(), [active.name], reason: 'no builder left');
        await expectUnchanged();
      },
    );

    test('the file is taken away between the two looks: "choose it again", '
        'nothing is switched', () async {
      await seedDevice();
      final archive = vaultFreeArchive(covers: true);

      final result = await restorer(
        activate: (g) async => fail('must not switch'),
        openLegacyDb: (path) {
          final chosen = File(archive);
          if (chosen.existsSync()) chosen.deleteSync();
          return sqlite3.open(path, mode: OpenMode.readOnly);
        },
      ).restore(archivePath: archive);

      final failure = result.getLeft().toNullable();
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).message,
        'The backup file could not be read. Please choose it again.',
      );
      expect(generationFolders(), [active.name], reason: 'no builder left');
      await expectUnchanged();
    });

    test('a work folder that cannot be made: nothing is read, nothing is '
        'switched', () async {
      await seedDevice();
      // A FILE where the folder of the run folders must be.
      Directory(p.dirname(workRoot())).createSync(recursive: true);
      File(workRoot()).writeAsBytesSync([0]);
      final vault = _FakeVault(right(VaultData.empty));

      final result = await restorer(
        vault: vault,
        activate: (g) async => fail('must not switch'),
      ).restore(archivePath: vaultFreeArchive());

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(vault.reads, 0);
      await expectUnchanged();
    });
  });

  group('BR6 — the cover count of a restore (D27)', () {
    test('rises to the number of covers and ends on it; nothing arrives '
        'after the restore has returned', () async {
      await seedDevice();
      final seen = <(int, int)>[];

      final result = await restorer().restore(
        archivePath: zip({
          'manifest.json': manifest(covers: true),
          'books.db': booksDb(),
          'wishlist.db': wishlistDb(),
          for (var i = 0; i < 5; i++) 'cover_c$i.jpg': [i, i, i],
        }),
        onProgress: (progress) =>
            seen.add((progress.coversDone, progress.coversTotal)),
      );

      expect(result.isRight(), isTrue);
      expect(seen, isNotEmpty);
      expect(seen.first.$2, 5);
      expect(seen.last, (5, 5));
      // The count never goes backwards and never repeats.
      final done = [for (final report in seen) report.$1];
      expect(done, [...done]..sort());
      expect(done.toSet(), hasLength(done.length));
      final count = seen.length;
      await pumpEventQueue();
      expect(seen, hasLength(count), reason: 'the port is closed');
    });

    test('carrying the device covers over is counted the same way', () async {
      await seedDevice(); // one cover on the device: old.jpg
      final seen = <(int, int)>[];

      final result = await restorer().restore(
        archivePath: vaultFreeArchive(coverRef: 'covers/old.jpg'),
        onProgress: (progress) =>
            seen.add((progress.coversDone, progress.coversTotal)),
      );

      expect(result.isRight(), isTrue);
      expect(seen.last, (1, 1));
    });

    test('a backup and a device without covers report nothing', () async {
      final seen = <(int, int)>[];

      final result = await restorer().restore(
        archivePath: vaultFreeArchive(),
        onProgress: (progress) =>
            seen.add((progress.coversDone, progress.coversTotal)),
      );
      await pumpEventQueue();

      expect(result.isRight(), isTrue);
      expect(seen, isEmpty);
    });

    test('a restore that fails closes its port too: nothing arrives '
        'later', () async {
      await seedDevice();
      final seen = <(int, int)>[];
      catalogues.failRebuild = true;

      final result = await restorer().restore(
        archivePath: vaultFreeArchive(covers: true),
        onProgress: (progress) =>
            seen.add((progress.coversDone, progress.coversTotal)),
      );
      await pumpEventQueue();

      expect(result.isLeft(), isTrue);
      expect(seen, isEmpty, reason: 'the covers step was never reached');
      await expectUnchanged();
    });
  });

  group('a write to the live catalogue while the restore copies it', () {
    // The restorer asks for the active generation as its LAST step before
    // it copies the catalogue. Taking the lock inside that question puts it
    // exactly where the copy meets it, however long the steps before took.

    test('the copy waits for a write lock that goes away, and the restore '
        'succeeds', () async {
      await seedDevice();
      late _HeldWriteLock lock;

      final result = await restorer(
        activeGeneration: () async {
          lock = await _HeldWriteLock.take(
            active.catalogueDbPath,
            // Far longer than the few lines between here and the copy, far
            // shorter than the copy is willing to wait.
            atMost: const Duration(milliseconds: 300),
          );
          return active;
        },
      ).restore(archivePath: vaultFreeArchive());
      await lock.gone;

      final summary = result.getOrElse((f) => fail('unexpected: $f'));
      expect(summary.booksRestored, 1);
      expect(switched.single.name, isNot(active.name));
      expect(generations.open().name, switched.single.name);
      expect(runFolders(), isEmpty, reason: 'no run folder is left');
    });

    test('a write lock that outlasts the wait fails closed: a typed '
        'failure, the device unchanged, nothing left behind', () async {
      await seedDevice();
      late _HeldWriteLock lock;

      // This test sits out the app's real wait (about two seconds): the
      // wait is one number in one place, with no second way in for tests.
      final result = await restorer(
        activeGeneration: () async {
          lock = await _HeldWriteLock.take(
            active.catalogueDbPath,
            // Held until this test lets go, below: the wait cannot win.
            atMost: const Duration(seconds: 30),
          );
          return active;
        },
      ).restore(archivePath: vaultFreeArchive());
      // `expectUnchanged` reads the live catalogue: only once it is free.
      lock.release();
      await lock.gone;

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      await expectUnchanged();
    });

    test('the wait stays under the five seconds after which Android calls '
        'an app unresponsive', () {
      // The wait blocks the screen's thread (see the constant's comment).
      expect(restoreSnapshotBusyWaitMs, lessThan(5000));
    });
  });

  group('crash simulation: startup recovery', () {
    test('a fully built but never-switched generation is discarded at the '
        'next open and the old data is still active', () async {
      await seedDevice();
      // Build everything, then "crash" before the pointer rename.
      final result = await restorer(
        activate: (g) async => throw StateError('simulated crash'),
      ).restore(archivePath: vaultFreeArchive());
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
