import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

void main() {
  late Directory tmp;
  late VaultStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vault_store_test');
    store = VaultStore(baseDir: tmp.path);
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('uninitialized when neither artifact exists', () {
    expect(store.isInitialized(), isFalse);
    expect(store.readBlob(), isNull);
  });

  test('not initialized with only the blob (db missing)', () {
    store.writeBlob('salt.iv.ct');
    expect(store.isInitialized(), isFalse);
  });

  test('initialized once both the db file and blob exist', () {
    File(store.dbPath).writeAsBytesSync([1, 2, 3]);
    store.writeBlob('salt.iv.ct');
    expect(store.isInitialized(), isTrue);
  });

  test('writeBlob then readBlob round-trips and trims whitespace', () {
    store.writeBlob('  salt.iv.ct\n');
    expect(store.readBlob(), 'salt.iv.ct');
  });

  test('dbPath is borrowers.db under the base dir', () {
    expect(p.basename(store.dbPath), 'borrowers.db');
    expect(p.dirname(store.dbPath), tmp.path);
  });

  test('clear removes both artifacts and is idempotent', () {
    File(store.dbPath).writeAsBytesSync([1]);
    store.writeBlob('a.b.c');
    expect(store.isInitialized(), isTrue);

    store.clear();
    expect(store.isInitialized(), isFalse);
    expect(store.readBlob(), isNull);

    // Idempotent: clearing again does not throw.
    expect(store.clear, returnsNormally);
  });

  group('atomic blob writes (review 2026-09-03, Blocker)', () {
    test('writeBlob leaves no temp file and the live blob is complete', () {
      store
        ..writeBlob('old.blob.value')
        ..writeBlob('new.blob.value');
      expect(store.readBlob(), 'new.blob.value');
      final leftovers = tmp
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => n.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('a failing writeBlob keeps the OLD blob intact', () {
      store.writeBlob('old.blob.value');
      // Make the temp path unwritable by planting a DIRECTORY where the temp
      // file would go — writeAsStringSync then throws before any rename.
      Directory(p.join(tmp.path, 'vault_backup_blob.tmp')).createSync();
      expect(
        () => store.writeBlob('new.blob.value'),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.readBlob(), 'old.blob.value');
    });

    test('writeBioBlob is atomic too', () {
      store.writeBioBlob('bio.one.x');
      Directory(p.join(tmp.path, 'vault_biometric_blob.tmp')).createSync();
      expect(
        () => store.writeBioBlob('bio.two.y'),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.readBioBlob(), 'bio.one.x');
    });
  });

  group('orphan database (half-created vault)', () {
    test('a DB with no blob is an orphan; a real vault is not', () {
      expect(store.hasOrphanDatabase(), isFalse); // nothing at all
      File(store.dbPath).writeAsBytesSync([1]);
      expect(store.hasOrphanDatabase(), isTrue); // DB, no blob
      store.writeBlob('a.b.c');
      expect(store.hasOrphanDatabase(), isFalse); // real vault
    });

    test('a blank (truncated) blob also counts as an orphan', () {
      File(store.dbPath).writeAsBytesSync([1]);
      File(p.join(tmp.path, 'vault_backup_blob')).writeAsStringSync('');
      expect(store.isInitialized(), isTrue); // both files exist…
      expect(store.hasOrphanDatabase(), isTrue); // …but the key is gone
    });

    test(
      'discardOrphanDatabase removes only an orphan, never a real vault',
      () {
        File(store.dbPath).writeAsBytesSync([1]);
        store
          ..writeBioBlob('stale.bio.blob')
          ..discardOrphanDatabase();
        expect(File(store.dbPath).existsSync(), isFalse);
        expect(store.hasBioBlob(), isFalse);

        // Real vault: untouched.
        File(store.dbPath).writeAsBytesSync([2]);
        store
          ..writeBlob('real.key.blob')
          ..discardOrphanDatabase();
        expect(store.isInitialized(), isTrue);
        expect(File(store.dbPath).readAsBytesSync(), [2]);
        // Idempotent on nothing.
        store.clear();
        expect(store.discardOrphanDatabase, returnsNormally);
      },
    );
  });

  group('stageRestore / StagedVaultInstall (two-file commit)', () {
    late String srcDbPath;

    setUp(() {
      srcDbPath = p.join(tmp.path, 'staged_borrowers.db');
      File(srcDbPath).writeAsBytesSync([9, 8, 7]);
    });

    test('staging alone changes nothing live', () {
      File(store.dbPath).writeAsBytesSync([1]);
      store
        ..writeBlob('old.blob.x')
        ..stageRestore(dbSourcePath: srcDbPath, blob: 'new.blob.y');

      expect(File(store.dbPath).readAsBytesSync(), [1]);
      expect(store.readBlob(), 'old.blob.x');
    });

    test('commit installs DB + blob and clears the biometric blob', () {
      File(store.dbPath).writeAsBytesSync([1]);
      store
        ..writeBlob('old.blob.x')
        ..writeBioBlob('bio.blob.z');

      store.stageRestore(dbSourcePath: srcDbPath, blob: 'new.blob.y').commit();

      expect(File(store.dbPath).readAsBytesSync(), [9, 8, 7]);
      expect(store.readBlob(), 'new.blob.y');
      // Old bio blob wrapped the previous key → must be gone (re-enrol).
      expect(store.hasBioBlob(), isFalse);
      // No stray temps left behind.
      expect(
        tmp.listSync().where((e) => e.path.endsWith('.restore.tmp')).toList(),
        isEmpty,
      );
    });

    test('abort deletes temps and leaves the live vault untouched', () {
      store.writeBlob('old.blob.x');
      File(store.dbPath).writeAsBytesSync([1]);

      store.stageRestore(dbSourcePath: srcDbPath, blob: 'new.blob.y').abort();

      expect(File(store.dbPath).readAsBytesSync(), [1]);
      expect(store.readBlob(), 'old.blob.x');
      expect(
        tmp.listSync().where((e) => e.path.endsWith('.restore.tmp')).toList(),
        isEmpty,
      );
    });

    test('stageRestore on a missing source throws and leaves no temps', () {
      expect(
        () => store.stageRestore(
          dbSourcePath: p.join(tmp.path, 'nope.db'),
          blob: 'b',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        tmp.listSync().where((e) => e.path.endsWith('.restore.tmp')).toList(),
        isEmpty,
      );
    });

    test('commit rolls the blob back when the DB rename fails', () {
      store.writeBlob('old.blob.x');
      File(store.dbPath).writeAsBytesSync([1]);

      final staged = store.stageRestore(
        dbSourcePath: srcDbPath,
        blob: 'new.blob.y',
      );
      // Force the DB rename to fail: replace the live DB path with a
      // non-empty DIRECTORY — renameSync onto it raises.
      File(store.dbPath).deleteSync();
      Directory(store.dbPath).createSync();
      File(p.join(store.dbPath, 'occupied')).writeAsBytesSync([0]);

      expect(staged.commit, throwsA(isA<FileSystemException>()));
      // Fail closed: the OLD blob was restored, so the pre-restore vault
      // (had the dir not been our sabotage) would still be openable — never
      // a new-blob/old-db mismatch created by us.
      expect(store.readBlob(), 'old.blob.x');
    });

    test('commit is single-shot', () {
      final staged = store.stageRestore(dbSourcePath: srcDbPath, blob: 'b.l.o')
        ..commit();
      expect(staged.commit, throwsStateError);
    });
  });
}
