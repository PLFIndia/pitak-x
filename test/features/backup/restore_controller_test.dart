import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import '../vault/vault_repository_write_stub.dart';

/// Fake vault: never loads the native lib. Returns empty data (unused in the
/// corrupt-archive path, but required by the RestoreBackup constructor).
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
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_ctrl_test');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final restorer = RestoreBackup(
      db: db,
      vault: _FakeVault(),
      coversDir: '${tmp.path}/covers',
      workDir: '${tmp.path}/work',
    );
    final container = ProviderContainer(
      overrides: [restoreBackupProvider.overrideWith((ref) async => restorer)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('maps a corrupt archive to AsyncError(BackupCorruptFailure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([1, 2, 3]));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]), // not a zip
          passphrase: passphrase,
        );

    final state = container.read(restoreControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<BackupCorruptFailure>());
  });

  test('disposes the passphrase after restore (success or failure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([9, 9, 9]));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]),
          passphrase: passphrase,
        );

    // §6.1: the controller must wipe the secret; using it now must throw.
    expect(() => passphrase.use((b) => b), throwsStateError);
  });
}
