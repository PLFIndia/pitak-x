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
