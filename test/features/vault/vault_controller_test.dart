import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/open_vault_from_archive.dart';
import 'package:pitaka/features/vault/application/vault_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import 'vault_repository_write_stub.dart';

class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vault_ctrl_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final opener = OpenVaultFromArchive(
      vault: _FakeVault(),
      workDir: '${tmp.path}/work',
    );
    final container = ProviderContainer(
      overrides: [
        openVaultFromArchiveProvider.overrideWith((ref) async => opener),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('maps a corrupt archive to AsyncError(BackupCorruptFailure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([1, 2, 3]));

    await container
        .read(vaultControllerProvider.notifier)
        .open(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]), // not a zip
          passphrase: passphrase,
        );

    final state = container.read(vaultControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<BackupCorruptFailure>());
  });

  test('disposes the passphrase regardless of outcome', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([9, 9, 9]));

    await container
        .read(vaultControllerProvider.notifier)
        .open(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]),
          passphrase: passphrase,
        );

    // §6.1: the controller wipes the secret; using it now must throw.
    expect(() => passphrase.use((b) => b), throwsStateError);
  });
}
