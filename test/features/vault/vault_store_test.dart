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

  group('installRestored / copyFrom (M02: populate an EMPTY generation)', () {
    late String srcDbPath;
    late VaultStore next;

    setUp(() {
      srcDbPath = p.join(tmp.path, 'staged_borrowers.db');
      File(srcDbPath).writeAsBytesSync([9, 8, 7]);
      next = VaultStore(baseDir: p.join(tmp.path, 'next_generation'));
    });

    test('installRestored copies the DB and writes the blob into the empty '
        'store, with no biometric blob', () {
      next.installRestored(dbSourcePath: srcDbPath, blob: 'new.blob.y');

      expect(next.isInitialized(), isTrue);
      expect(File(next.dbPath).readAsBytesSync(), [9, 8, 7]);
      expect(next.readBlob(), 'new.blob.y');
      expect(next.hasBioBlob(), isFalse);
      // The source (a scratch copy) is left for the caller to clean up.
      expect(File(srcDbPath).existsSync(), isTrue);
    });

    test('installRestored refuses when ANY vault artifact already exists', () {
      next.writeBioBlob('stale.bio');

      expect(
        () => next.installRestored(dbSourcePath: srcDbPath, blob: 'b'),
        throwsStateError,
      );
      expect(File(next.dbPath).existsSync(), isFalse);
      expect(next.readBlob(), isNull);
    });

    test('installRestored on a missing source throws and writes nothing', () {
      expect(
        () => next.installRestored(
          dbSourcePath: p.join(tmp.path, 'nope.db'),
          blob: 'b',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(next.dbPath).existsSync(), isFalse);
      expect(next.readBlob(), isNull);
    });

    test('copyFrom carries DB, SQLite side files, key blob AND biometric blob '
        'over byte-for-byte', () {
      File(store.dbPath).writeAsBytesSync([1, 2, 3]);
      File('${store.dbPath}-journal').writeAsBytesSync([4]);
      File('${store.dbPath}-wal').writeAsBytesSync([5]);
      store
        ..writeBlob('old.blob.x')
        ..writeBioBlob('bio.blob.z');

      next.copyFrom(store);

      expect(File(next.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect(File('${next.dbPath}-journal').readAsBytesSync(), [4]);
      expect(File('${next.dbPath}-wal').readAsBytesSync(), [5]);
      expect(next.readBlob(), 'old.blob.x');
      expect(next.readBioBlob(), 'bio.blob.z');
      // The source is untouched (the old generation stays complete until the
      // pointer switch deletes it as a whole).
      expect(File(store.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect(store.readBlob(), 'old.blob.x');
    });

    test('copyFrom of an uninitialized source leaves the target empty', () {
      next.copyFrom(store);

      expect(next.isInitialized(), isFalse);
      expect(next.hasBioBlob(), isFalse);
    });

    test('copyFrom refuses when the target already holds a vault', () {
      File(store.dbPath).writeAsBytesSync([1]);
      store.writeBlob('old.blob.x');
      File(next.dbPath).parent.createSync(recursive: true);
      File(next.dbPath).writeAsBytesSync([7]);

      expect(() => next.copyFrom(store), throwsStateError);
      expect(File(next.dbPath).readAsBytesSync(), [7]);
      expect(next.readBlob(), isNull);
    });
  });
}
