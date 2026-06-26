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
}
