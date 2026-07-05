import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

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
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final restorer = RestoreBackup(
      db: db,
      vault: _FakeVault(),
      vaultStore: store,
      coversDir: '${tmp.path}/covers',
      workDir: '${tmp.path}/work',
    );
    final container = ProviderContainer(
      overrides: [
        restoreBackupProvider.overrideWith((ref) async => restorer),
        // The session controller's build() checks this store for the vault
        // files, so it must see the SAME directory the restorer installs into.
        vaultStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A minimal VALID archive that carries only a vault (no books/wishlist):
  /// manifest + backup_blob + borrowers.db. Restore installs the vault pair.
  Uint8List vaultOnlyArchive() {
    final manifest = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'exportedAt': 123,
        'hasBooks': false,
        'hasWishlist': false,
        'hasBorrowers': true,
        'hasBackupBlob': true,
        'hasCovers': false,
      }),
    );
    final blob = utf8.encode('blob-from-archive');
    final borrowersDb = utf8.encode('opaque-encrypted-db');
    final a = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('backup_blob', blob.length, blob))
      ..addFile(ArchiveFile('borrowers.db', borrowersDb.length, borrowersDb));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
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

  test('successful restore rebuilds the vault session (Create vault -> '
      'Unlock)', () async {
    final container = makeContainer();

    // Before restore: no vault on disk, so the session is Uninitialized —
    // this is the state that used to go STALE (keepAlive) after a restore.
    final before = await container.read(vaultSessionControllerProvider.future);
    expect(before, isA<VaultUninitialized>());

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: vaultOnlyArchive(),
          passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
        );
    expect(container.read(restoreControllerProvider).hasValue, isTrue);

    // The controller must invalidate the session so build() re-checks the
    // (now installed) vault files: Uninitialized -> Locked, i.e. the vault
    // page shows "Unlock" instead of "Create vault".
    final after = await container.read(vaultSessionControllerProvider.future);
    expect(after, isA<VaultLocked>());
  });

  test('failed restore leaves the vault session untouched', () async {
    final container = makeContainer();
    var rebuilds = 0;
    container.listen(
      vaultSessionControllerProvider,
      (_, _) => rebuilds++,
      fireImmediately: true,
    );
    await container.read(vaultSessionControllerProvider.future);
    final baseline = rebuilds;

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]), // not a zip
          passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
        );

    expect(container.read(restoreControllerProvider).hasError, isTrue);
    // No invalidation on failure: nothing on disk changed, so no rebuild.
    expect(rebuilds, baseline);
    expect(
      await container.read(vaultSessionControllerProvider.future),
      isA<VaultUninitialized>(),
    );
  });
}
