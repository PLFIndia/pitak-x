import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/open_vault_from_archive.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import 'vault_repository_write_stub.dart';

/// Fake vault: never loads the native lib. Records the last call and returns a
/// configurable result so we can assert routing without real crypto.
class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  _FakeVault(this._result);
  final Either<Failure, VaultData> _result;
  String? lastDbPath;
  bool called = false;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    called = true;
    lastDbPath = dbPath;
    return _result;
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('open_vault_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SecretBytes pass() => SecretBytes(Uint8List.fromList([1, 2, 3]));

  Uint8List archive(Map<String, List<int>> entries) {
    final a = Archive();
    entries.forEach((k, v) => a.addFile(ArchiveFile(k, v.length, v)));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  }

  String manifest({int schemaVersion = 1, bool hasBackupBlob = true}) =>
      jsonEncode({
        'schemaVersion': schemaVersion,
        'exportedAt': 123,
        'hasBooks': true,
        'hasWishlist': true,
        'hasBorrowers': hasBackupBlob,
        'hasBackupBlob': hasBackupBlob,
        'hasCovers': false,
      });

  OpenVaultFromArchive opener(VaultRepository vault) =>
      OpenVaultFromArchive(vault: vault, workDir: '${tmp.path}/work');

  test('unlocks and returns vault data on a valid archive', () async {
    const data = VaultData(
      borrowers: [Borrower(id: 1, name: 'Asha')],
      loans: [Loan(id: 1, bookId: 5, borrowerId: 1, lentDate: 100)],
    );
    final vault = _FakeVault(right(data));
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'borrowers.db': [1, 2, 3],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });

    final result = await opener(
      vault,
    ).open(archiveBytes: zip, passphrase: pass());

    expect(result.isRight(), isTrue);
    expect(vault.called, isTrue);
    expect(vault.lastDbPath, contains('borrowers.db'));
    final out = result.getOrElse((_) => fail('expected data'));
    expect(out.borrowers.single.name, 'Asha');
  });

  test('removes the staged DB after reading (no residue)', () async {
    final vault = _FakeVault(right(VaultData.empty));
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'borrowers.db': [1, 2, 3],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });

    await opener(vault).open(archiveBytes: zip, passphrase: pass());

    expect(Directory('${tmp.path}/work').existsSync(), isFalse);
  });

  test('manifest with no vault returns empty data, never calls FFI', () async {
    final vault = _FakeVault(right(VaultData.empty));
    final zip = archive({
      'manifest.json': utf8.encode(manifest(hasBackupBlob: false)),
    });

    final result = await opener(
      vault,
    ).open(archiveBytes: zip, passphrase: pass());

    expect(result.isRight(), isTrue);
    expect(vault.called, isFalse);
  });

  test('schema newer than known is refused', () async {
    final vault = _FakeVault(right(VaultData.empty));
    final zip = archive({
      'manifest.json': utf8.encode(manifest(schemaVersion: 99)),
    });

    final result = await opener(
      vault,
    ).open(archiveBytes: zip, passphrase: pass());

    expect(result.fold((f) => f, (_) => null), isA<SchemaTooNewFailure>());
    expect(vault.called, isFalse);
  });

  test('a non-zip blob is a corrupt archive', () async {
    final vault = _FakeVault(right(VaultData.empty));
    final result = await opener(
      vault,
    ).open(archiveBytes: Uint8List.fromList([0, 1, 2, 3]), passphrase: pass());
    expect(result.fold((f) => f, (_) => null), isA<BackupCorruptFailure>());
  });

  test('a wrong-passphrase failure from the repo propagates', () async {
    final vault = _FakeVault(left(const WrongPassphraseFailure()));
    final zip = archive({
      'manifest.json': utf8.encode(manifest()),
      'borrowers.db': [1, 2, 3],
      'backup_blob': utf8.encode('salt.iv.ct'),
    });

    final result = await opener(
      vault,
    ).open(archiveBytes: zip, passphrase: pass());

    expect(result.fold((f) => f, (_) => null), isA<WrongPassphraseFailure>());
  });
}
