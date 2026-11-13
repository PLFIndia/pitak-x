/// Applies a Pitaka backup archive to this device — the crux of the port's
/// "zero data loss" guarantee.
///
/// Restore is an AUTHORITATIVE OVERWRITE of local state, not an additive merge
/// (mirrors Kotlin `BackupRestore`). Ordering is fail-closed: everything that
/// can fail without side effects (reading the archive, manifest, blob unwrap)
/// happens BEFORE any device write.
///
/// ATOMIC across stores (review finding M02: restore used to commit the
/// catalogue before the vault, so a failure in between mixed old and new
/// stores): the catalogue database, the
/// covers and the vault are never edited in place. Restore BUILDS a complete
/// new data generation directory (see `core/storage/data_generations.dart`) —
/// a transactionally consistent snapshot of the live catalogue that is then
/// replaced inside its own transaction, the archive's covers, and either the
/// archive's vault pair or a byte-for-byte copy of the retained one — marks it
/// COMPLETE, and only then switches the single `CURRENT` pointer with one
/// atomic rename. Any failure before that switch discards the builder
/// directory and leaves the active generation byte-identical. A crash before
/// the switch is cleaned up by startup recovery; a crash after it is simply a
/// successful restore. There is no window in which the device runs on a mix of
/// old and new catalogue, vault and covers.
///
/// READ FROM A FILE, IN WORKERS (backup rework BR6, review finding P3-B3):
/// the backup is a FILE (the private copy the app's picker made), never
/// bytes in memory. A worker isolate checks it and takes the small entries
/// and the three databases (`restore_archive_reader.dart`); a second worker
/// writes the cover pictures one by one into the new generation
/// (`restore_covers_builder.dart`). What a restore holds in memory no
/// longer grows with the backup, and the screen keeps painting. The
/// archive file is only read here: never written, never deleted (its owner
/// is the caller).
///
/// The scratch files of one restore (the staged databases) live in a
/// folder of their own under the app's temporary folder
/// (`RunFolders`), made at the start of [RestoreBackup.restore] and removed
/// at its end on every way out.
///
/// Trust boundary: the encrypted `borrowers.db` + vault key live entirely in
/// the Rust core (via [VaultRepository]); the plain `books.db`/`wishlist.db`
/// are read here with `sqlite3` (no secrets). The vault key never reaches Dart.
///
/// Neighbours (split out under the file-size ratchet, B8): the archive-entry
/// readers are `backup_extras_reader.dart`, the legacy-DB read phase is
/// `restore_legacy_read.dart`, the ADR 0014 W2 kinds/details join +
/// write helpers are `restore_item_details.dart`, the catalogue write of
/// phase 6a is `restore_catalogue_builder.dart`, the covers of phase 6b are
/// `restore_covers_builder.dart`, and the summary of phase 8 is
/// `restore_summary_builder.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart'
    show backupBlobEntryName;
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/backup_progress_port.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_catalogue_builder.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/backup/infrastructure/restore_item_details.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/backup/infrastructure/restore_summary_builder.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// What the user reads when the backup file itself can no longer be opened
/// or read (the private copy is gone: the system may clear the app's
/// temporary folder when storage is short). A sentence of its own, because
/// "could not write the restored data" would be untrue, and because there
/// is something the user can do.
const String restoreArchiveUnreadableMessage =
    'The backup file could not be read. Please choose it again.';

/// Opens the app's Drift catalogue at an arbitrary file path (the builder
/// generation's copy). Injectable so tests can inject faults into it.
typedef CatalogueOpener = AppDatabase Function(String path);

/// Resolves the generation the app is currently running on.
typedef ActiveGenerationResolver = Future<DataGeneration> Function();

/// Switches the app onto a COMPLETE generation (the DI implementation goes
/// through `ActiveDataGeneration.activate`, which also republishes the paths
/// so database/covers/vault providers rebuild). Throws on failure.
typedef GenerationActivator =
    Future<DataGeneration> Function(DataGeneration generation);

CommonDatabase _defaultOpen(String path) =>
    sqlite3.open(path, mode: OpenMode.readOnly);

AppDatabase _defaultOpenCatalogue(String path) =>
    AppDatabase(NativeDatabase(File(path)));

/// Restores a backup archive by building and activating a new data generation.
final class RestoreBackup {
  /// Creates the restorer.
  ///
  /// [vault] reads the encrypted borrowers DB through the Rust core;
  /// [generations] owns the generation directories; [activeGeneration]
  /// resolves the live one (its catalogue is snapshotted, its vault/covers
  /// carried over where the archive lacks them); [activate] performs the
  /// atomic switch; [openCatalogue] opens the builder's catalogue copy;
  /// [workFolders] hands out the scratch folder of one restore and removes
  /// it again; [replacementGuard] serialises this operation against vault
  /// work (M03). [limits] is what one backup may hold; the app uses the
  /// default, tests pass small limits.
  RestoreBackup({
    required this.vault,
    required this.generations,
    required this.activeGeneration,
    required this.activate,
    required this.workFolders,
    required this.replacementGuard,
    this.limits = BackupLimits.current,
    CatalogueOpener openCatalogue = _defaultOpenCatalogue,
    LegacyDbOpener openLegacyDb = _defaultOpen,
  }) : _openCatalogue = openCatalogue,
       _open = openLegacyDb;

  /// Vault reader over the Rust FFI core.
  final VaultRepository vault;

  /// Generation directory store (build / complete / activate / discard).
  final DataGenerations generations;

  /// Resolves the generation currently active.
  final ActiveGenerationResolver activeGeneration;

  /// Performs the atomic switch onto a completed generation.
  final GenerationActivator activate;

  /// The private scratch folders of restores: one new folder per call of
  /// [restore], for the staged databases.
  final RunFolders workFolders;

  /// Shared session guard: no vault operations overlap this replacement.
  final CatalogueReplacementGuard replacementGuard;

  /// What one backup may hold. The reader's rules are built from it.
  final BackupLimits limits;

  final CatalogueOpener _openCatalogue;
  final LegacyDbOpener _open;

  /// Inspects the backup file at [archivePath] WITHOUT restoring anything
  /// (N13): the file is checked and the manifest read, plus the two
  /// additive entries the page shows (§5.10), so the UI can name the
  /// identity and the website it would adopt. Reads no database, unlocks
  /// nothing, stages nothing, and touches no device state.
  Future<Either<Failure, ArchiveInspection>> inspectArchive(
    String archivePath,
  ) async {
    final parts = await readRestoreArchiveInWorker((
      archivePath: archivePath,
      limits: limits,
      workDir: null,
    ));
    final stopped = _failureOf(parts.refusal, parts.trouble);
    if (stopped != null) return left(stopped);
    return parseBackupManifest(parts.entries).map((manifest) {
      final extras = readBackupExtras(
        parts.entries,
        manifest,
        carriedCoverLeaves: parts.coversToWrite.toSet(),
      );
      return ArchiveInspection(
        manifest: manifest,
        identity: extras.identity,
        publishState: extras.publishState,
      );
    });
  }

  /// Applies the backup file at [archivePath], unlocking the vault with
  /// [passphrase] when the archive carries one. The caller owns
  /// [passphrase] and must dispose it, and owns the file: it is only read
  /// here.
  ///
  /// [passphrase] is null only when the archive holds NO vault (N13: a
  /// vault-free backup needs no passphrase); when the manifest says a vault
  /// is present but no passphrase was supplied, restore fails closed.
  ///
  /// [onProgress] hears how many cover pictures are written, of how many,
  /// a few times a second (decision D27). It is called on this isolate.
  ///
  /// Returns a typed [Failure] on any problem. On failure the device is left
  /// EXACTLY on its pre-restore generation: nothing live is ever written.
  Future<Either<Failure, RestoreSummary>> restore({
    required String archivePath,
    SecretBytes? passphrase,
    BackupProgressListener? onProgress,
  }) async {
    // --- Phase 1: a scratch folder of this restore's own ---
    final workDir = await workFolders.create(sweepFirst: true);
    if (workDir == null) {
      return left(const StorageFailure('Could not create work dir'));
    }
    // The port the covers worker reports to. Opened only when somebody
    // listens, as the LAST step before the `try`, whose `finally` closes it
    // on every way out.
    final progress = onProgress == null
        ? null
        : BackupProgressReceiver(onProgress);
    try {
      // --- Phase 2: read the archive in a worker (no device writes) ---
      final parts = await readRestoreArchiveInWorker((
        archivePath: archivePath,
        limits: limits,
        workDir: workDir,
      ));
      final stopped = _failureOf(parts.refusal, parts.trouble);
      if (stopped != null) return left(stopped);

      // --- Phase 3: manifest, refuse schemaVersion > known ---
      final parsed = parseBackupManifest(parts.entries);
      final manifest = parsed.toNullable();
      if (manifest == null) {
        return parsed.map((_) => throw StateError('unreachable'));
      }

      // The guard also ends the vault session afterwards: even a retained
      // vault moves to a new directory, so a cached store/key must not
      // survive.
      return await replacementGuard.protectReplacement(
        (scope) => _restoreValidated(
          archivePath: archivePath,
          parts: parts,
          manifest: manifest,
          passphrase: passphrase,
          scope: scope,
          progress: progress,
        ),
        replacingVault: manifest.hasBackupBlob,
        endsSession: true,
      );
    } finally {
      // On EVERY way out. The port first: closing it cannot fail. The
      // scratch folder holds plain copies of the databases; when it cannot
      // be removed now, the next restore and the next app start sweep it.
      progress?.close();
      await workFolders.discard(workDir);
    }
  }

  Future<Either<Failure, RestoreSummary>> _restoreValidated({
    required String archivePath,
    required RestoreArchiveParts parts,
    required BackupManifest manifest,
    required SecretBytes? passphrase,
    required CatalogueReplacementScope scope,
    required BackupProgressReceiver? progress,
  }) async {
    // --- Additive extras: parse (never apply) identity, network list and
    // the W2 item-details entries up front. An invalid entry is reported on
    // the summary, never aborts (additive). An entry the worker did not
    // hand over (missing, or above its cap) reads as unreadable too.
    final extras = readBackupExtras(
      parts.entries,
      manifest,
      // The publishing record believes only in covers this restore WRITES.
      carriedCoverLeaves: parts.coversToWrite.toSet(),
    );

    DataGeneration? builder;
    try {
      // --- Phase 4: vault unlock (no device writes yet; fail closed) ---
      var vaultData = VaultData.empty;
      String? stagedVaultDbPath;
      String? vaultBlob;
      if (manifest.hasBackupBlob) {
        // N13 fail-closed: a vault-bearing archive MUST come with a
        // passphrase; the UI only omits the field for vault-free archives.
        if (passphrase == null) {
          return left(
            const ValidationFailure(
              'This backup contains an encrypted borrowers vault. Enter its '
              'passphrase to restore.',
            ),
          );
        }
        final blobBytes = parts.entries[backupBlobEntryName];
        final borrowersPath = parts.borrowersDbPath;
        if (blobBytes == null) {
          return left(
            const BackupCorruptFailure('Archive missing backup_blob'),
          );
        }
        if (borrowersPath == null) {
          return left(
            const BackupCorruptFailure('Archive missing borrowers.db'),
          );
        }
        final blob = _utf8(blobBytes).trim();
        final unlocked = await vault.unlockAndRead(
          passphrase: passphrase,
          blob: blob,
          dbPath: borrowersPath,
        );
        // A wrong passphrase / corrupt vault aborts BEFORE any device write.
        final early = unlocked.match<Failure?>((f) => f, (data) {
          vaultData = data;
          return null;
        });
        if (early != null) return left(early);
        stagedVaultDbPath = borrowersPath;
        vaultBlob = blob;
      }

      // --- Phase 5: read legacy books/wishlist (still no device writes) ---
      // On THIS isolate: the opener is a seam of the tests, and a function
      // cannot be sent to a worker.
      final readResult = readLegacyCatalogue(
        booksDbPath: parts.booksDbPath,
        wishlistDbPath: parts.wishlistDbPath,
        manifest: manifest,
        open: _open,
      );
      final legacy = readResult.toNullable();
      if (legacy == null) {
        return readResult.map((_) => throw StateError('unreachable'));
      }
      if (!scope.isCurrent) return left(CatalogueReplacementScope.cancelled);

      // --- Phase 5b (W2): join kinds + issue details onto the legacy rows
      // BEFORE the catalogue write, so the write is one straight pass. The
      // counts ride into the summary. Absent/unreadable entries apply
      // nothing (the invalid flags below tell the two apart).
      final applied = applyRestoredItemDetails(
        books: legacy.books,
        kinds: extras.itemKinds,
        periodicals: extras.periodicals,
      );
      legacy
        ..books = applied.books
        ..periodicals = applied.periodicals;

      // --- Phase 6: BUILD the next generation (no live effect) ---
      // Everything below writes only into the builder directory. Any failure
      // is caught, the directory discarded, and the device is unchanged.
      final active = await activeGeneration();
      builder = generations.beginNext(active);

      // 6a. catalogue: consistent snapshot of the live DB, then replace inside
      // a transaction on THAT copy. `VACUUM INTO` copies schema, indexes,
      // FTS shadow tables and sqlite_sequence (so M03's no-ID-reuse holds).
      final catalogueResult = await buildRestoredCatalogue(
        active: active,
        builder: builder,
        legacy: legacy,
        scope: scope,
        openCatalogue: _openCatalogue,
      );
      if (catalogueResult.isLeft()) {
        return catalogueResult.map((_) => throw StateError('unreachable'));
      }

      // 6b. covers, in a worker: the archive's set when it has one, written
      // one by one from the file; otherwise the device's covers are carried
      // over (restored rows may still reference them). After the catalogue
      // on purpose: a wrong passphrase or a refused row is found before any
      // cover is written.
      final covers = await buildRestoredCoversInWorker((
        archivePath: archivePath,
        limits: limits,
        coversToWrite: manifest.hasCovers ? parts.coversToWrite : null,
        activeCoversDir: active.coversDir,
        builderCoversDir: builder.coversDir,
        progressPort: progress?.sendPort,
      ));
      final coversStopped = _failureOf(covers.refusal, covers.trouble);
      if (coversStopped != null) return left(coversStopped);

      // 6c. vault: the archive's validated pair, or the retained device vault
      // copied byte-for-byte (the guard holds the FIFO, so nothing writes it).
      final nextStore = VaultStore(baseDir: builder.vaultDir);
      if (stagedVaultDbPath != null && vaultBlob != null) {
        nextStore.installRestored(
          dbSourcePath: stagedVaultDbPath,
          blob: vaultBlob,
        );
      } else if (scope.retainedLoanBookIds != null) {
        nextStore.copyFrom(VaultStore(baseDir: active.vaultDir));
      }

      // --- Phase 7: COMPLETE, then the single atomic switch ---
      generations.complete(builder);
      // The lease is checked last: a lock/disposal during the build must not
      // be followed by a switch that reports success for a session that ended.
      if (!scope.isCurrent) return left(CatalogueReplacementScope.cancelled);
      // After the pointer rename, `builder` is live. Old-generation cleanup
      // is best-effort, so a failed delete cannot make `discard` target it.
      await activate(builder);
      builder = null; // now live: never discard it in `finally`

      // --- Phase 8: cross-DB loan integrity and the summary ---
      return right(
        summariseRestore(
          manifest: manifest,
          extras: extras,
          legacy: legacy,
          applied: applied,
          vaultData: vaultData,
          // M03: a retained vault was freshly checked by the guard; every
          // loan's book identity was preserved by the plan, or we refused.
          existingVaultKept: scope.retainedLoanBookIds != null,
          coversLeftOut: parts.coversLeftOut,
        ),
      );
    } on FileSystemException catch (e) {
      return left(
        StorageFailure('Restore could not write files: ${e.message}'),
      );
    } on Object catch (e) {
      // Drift/SQLite/VACUUM failures inside the builder; the message never
      // includes vault secrets (the vault is only ever copied as bytes).
      return left(StorageFailure('Restore failed before activation: $e'));
    } finally {
      // Fail closed: a builder that did not become live is removed so no
      // second copy of the catalogue lingers (privacy) and no half-built
      // generation can be mistaken for data. Startup recovery covers a crash.
      final abandoned = builder;
      if (abandoned != null) {
        try {
          generations.discard(abandoned);
        } on FileSystemException {
          // Startup recovery deletes it on the next launch.
        }
      }
    }
  }

  /// The typed failure for what a worker answered, or null when it did not
  /// stop. Made HERE, on the calling isolate: no [Failure] object crosses
  /// the isolate border, only a refusal's text or a code for the disk.
  static Failure? _failureOf(String? refusal, RestoreDiskTrouble? trouble) {
    if (refusal != null) return BackupCorruptFailure(refusal);
    return switch (trouble) {
      null => null,
      RestoreDiskTrouble.archiveUnreadable => const ValidationFailure(
        restoreArchiveUnreadableMessage,
      ),
      RestoreDiskTrouble.targetUnwritable => const StorageFailure(
        'Restore could not write files',
      ),
    };
  }

  static String _utf8(Uint8List bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);
}
