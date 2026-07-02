/// Read-only vault opener (application layer, AGENTS.md §3/§4).
///
/// Opens a `.pitabak` archive and the passphrase, unlocks the encrypted
/// `borrowers.db` through the Rust FFI core, and returns the borrowers + loans.
/// It writes NOTHING to device state (unlike `RestoreBackup`): the vault DB is
/// staged into a scratch dir, read, and the scratch dir is removed.
///
/// This is all the ported data layer supports today — the Rust core is
/// read-only (no vault write path). It is also the one place the real native
/// FFI runs from a live screen (see PLAN Step 16 / HANDOFF §6.3).
///
/// Trust boundary: the vault key never crosses into Dart; only decrypted rows
/// come back. The caller owns the [SecretBytes] passphrase and disposes it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

/// Stable `.pitabak` entry names (mirror of the restore archive contract).
const String _manifestEntry = 'manifest.json';
const String _borrowersDbEntry = 'borrowers.db';
const String _backupBlobEntry = 'backup_blob';

/// Opens and reads an encrypted vault from a backup archive, read-only.
final class OpenVaultFromArchive {
  /// Creates the opener.
  ///
  /// [vault] reads the encrypted DB through the Rust core; [workDir] is a
  /// scratch dir the `borrowers.db` is staged into (created fresh, removed
  /// after the read).
  const OpenVaultFromArchive({required this.vault, required this.workDir});

  /// Vault reader over the Rust FFI core.
  final VaultRepository vault;

  /// Absolute path of a scratch directory for the staged DB.
  final String workDir;

  /// Extracts [archiveBytes], stages `borrowers.db`, and unlocks it with
  /// [passphrase]. The caller owns [passphrase] and must dispose it.
  ///
  /// Returns [VaultData] on success, or a typed [Failure]:
  ///  - the archive is corrupt / missing entries → [BackupCorruptFailure]
  ///  - the manifest declares no vault → empty [VaultData]
  ///  - schema too new → [SchemaTooNewFailure]
  ///  - wrong passphrase → [WrongPassphraseFailure] (from the repo)
  Future<Either<Failure, VaultData>> open({
    required Uint8List archiveBytes,
    required SecretBytes passphrase,
  }) async {
    // Phase 1: bounded extract (no device writes).
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(archiveBytes);
    } on BoundedExtractionException catch (e) {
      return left(BackupCorruptFailure(e.message));
    }

    // Phase 2: manifest gate (refuse a newer schema, like restore).
    final manifestBytes = files[_manifestEntry];
    if (manifestBytes == null) {
      return left(const BackupCorruptFailure('Archive missing manifest.json'));
    }
    final manifest = BackupManifest.tryParse(_utf8(manifestBytes));
    if (manifest == null) {
      return left(const BackupCorruptFailure('Invalid manifest.json'));
    }
    if (manifest.schemaVersion > BackupManifest.knownSchemaVersion) {
      return left(SchemaTooNewFailure(manifest.schemaVersion));
    }
    if (!manifest.hasBackupBlob) {
      // A valid backup with no vault — nothing to show, not an error.
      return right(VaultData.empty);
    }

    final blobBytes = files[_backupBlobEntry];
    final borrowersBytes = files[_borrowersDbEntry];
    if (blobBytes == null) {
      return left(const BackupCorruptFailure('Archive missing backup_blob'));
    }
    if (borrowersBytes == null) {
      return left(const BackupCorruptFailure('Archive missing borrowers.db'));
    }

    // Phase 3: stage the DB to a fresh scratch dir (FFI needs a path).
    final Directory work;
    try {
      work = Directory(workDir);
      if (work.existsSync()) work.deleteSync(recursive: true);
      work.createSync(recursive: true);
    } on FileSystemException catch (e) {
      return left(StorageFailure('Could not create work dir: ${e.message}'));
    }

    try {
      final dbPath = p.join(work.path, _borrowersDbEntry);
      File(dbPath).writeAsBytesSync(borrowersBytes);
      // Phase 4: unlock + read through the Rust core (no device writes).
      return await vault.unlockAndRead(
        passphrase: passphrase,
        blob: _utf8(blobBytes).trim(),
        dbPath: dbPath,
      );
    } on Object catch (e) {
      return left(StorageFailure('vault open: $e'));
    } finally {
      // Always remove the staged plaintext-handle DB after reading.
      if (work.existsSync()) {
        try {
          work.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup; nothing sensitive (the key never hit disk).
        }
      }
    }
  }

  static String _utf8(Uint8List bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);
}
