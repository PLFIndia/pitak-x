/// Applies a Pitaka backup archive to this device — the crux of the port's
/// "zero data loss" guarantee.
///
/// Restore is an AUTHORITATIVE OVERWRITE of local state, not an additive merge
/// (mirrors Kotlin `BackupRestore`). Ordering is fail-closed: everything that
/// can fail without side effects (extract, manifest, blob unwrap) happens
/// BEFORE any device write.
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
/// Trust boundary: the encrypted `borrowers.db` + vault key live entirely in
/// the Rust core (via [VaultRepository]); the plain `books.db`/`wishlist.db`
/// are read here with `sqlite3` (no secrets). The vault key never reaches Dart.
///
/// Neighbours (split out under the file-size ratchet, B8): the archive-entry
/// readers are `backup_extras_reader.dart`, the legacy-DB read phase is
/// `restore_legacy_read.dart`, and the ADR 0014 W2 kinds/details join +
/// write helpers are `restore_item_details.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/backup/infrastructure/restore_item_details.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/infrastructure/wishlist_mapper.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// ZIP entry names of the archive's encrypted vault pair.
const String _borrowersDbEntry = 'borrowers.db';
const String _backupBlobEntry = 'backup_blob';

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
  /// [workDir] is a scratch dir for extracted files; [replacementGuard]
  /// serialises this operation against vault work (M03).
  RestoreBackup({
    required this.vault,
    required this.generations,
    required this.activeGeneration,
    required this.activate,
    required this.workDir,
    required this.replacementGuard,
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

  /// Absolute path of a scratch directory for extracted files.
  final String workDir;

  /// Shared session guard: no vault operations overlap this replacement.
  final CatalogueReplacementGuard replacementGuard;

  final CatalogueOpener _openCatalogue;
  final LegacyDbOpener _open;

  /// Inspects [archiveBytes] WITHOUT restoring anything (N13): bounded
  /// extract + manifest parse only, plus a peek at `identity.json` when the
  /// manifest announces one (§5.10) so the UI can name the identity it would
  /// adopt. Reads no database rows, unlocks nothing, and touches no device
  /// state.
  Future<Either<Failure, ArchiveInspection>> inspectArchive(
    Uint8List archiveBytes,
  ) async {
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(archiveBytes);
    } on BoundedExtractionException catch (e) {
      return left(BackupCorruptFailure(e.message));
    }
    return parseBackupManifest(files).map(
      (manifest) => ArchiveInspection(
        manifest: manifest,
        identity: readBackupExtras(files, manifest).identity,
      ),
    );
  }

  /// Applies [archiveBytes], unlocking the vault with [passphrase] when the
  /// archive carries one. The caller owns [passphrase] and must dispose it.
  ///
  /// [passphrase] is null only when the archive holds NO vault (N13: a
  /// vault-free backup needs no passphrase); when the manifest says a vault
  /// is present but no passphrase was supplied, restore fails closed.
  ///
  /// Returns a typed [Failure] on any problem. On failure the device is left
  /// EXACTLY on its pre-restore generation: nothing live is ever written.
  Future<Either<Failure, RestoreSummary>> restore({
    required Uint8List archiveBytes,
    SecretBytes? passphrase,
  }) async {
    // --- Phase 1: extract (no device writes yet) ---
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(archiveBytes);
    } on BoundedExtractionException catch (e) {
      return left(BackupCorruptFailure(e.message));
    }

    // --- Phase 2: manifest, refuse schemaVersion > known ---
    final parsed = parseBackupManifest(files);
    final manifest = parsed.toNullable();
    if (manifest == null) {
      return parsed.map((_) => throw StateError('unreachable'));
    }

    // The guard also ends the vault session afterwards: even a retained vault
    // moves to a new directory, so a cached store/key must not survive.
    return replacementGuard.protectReplacement(
      (scope) => _restoreValidated(files, manifest, passphrase, scope),
      replacingVault: manifest.hasBackupBlob,
      endsSession: true,
    );
  }

  Future<Either<Failure, RestoreSummary>> _restoreValidated(
    Map<String, Uint8List> files,
    BackupManifest manifest,
    SecretBytes? passphrase,
    CatalogueReplacementScope scope,
  ) async {
    // --- Additive extras: parse (never apply) identity, network list and
    // the W2 item-details entries up front. An invalid entry is reported on
    // the summary, never aborts (additive).
    final extras = readBackupExtras(files, manifest);
    final identity = extras.identity;
    final network = extras.network;

    // --- Phase 3: stage archive files to disk (sqlite3 + FFI need paths) ---
    final Directory work;
    try {
      work = Directory(workDir);
      if (work.existsSync()) work.deleteSync(recursive: true);
      work.createSync(recursive: true);
    } on FileSystemException catch (e) {
      return left(StorageFailure('Could not create work dir: ${e.message}'));
    }

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
        final blobBytes = files[_backupBlobEntry];
        final borrowersBytes = files[_borrowersDbEntry];
        if (blobBytes == null) {
          return left(
            const BackupCorruptFailure('Archive missing backup_blob'),
          );
        }
        if (borrowersBytes == null) {
          return left(
            const BackupCorruptFailure('Archive missing borrowers.db'),
          );
        }
        final borrowersPath = stageArchiveEntry(
          work,
          _borrowersDbEntry,
          borrowersBytes,
        );
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
      final readResult = readLegacyCatalogue(work, files, manifest, _open);
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
      final catalogueResult = await _buildCatalogue(
        active: active,
        builder: builder,
        legacy: legacy,
        scope: scope,
      );
      if (catalogueResult.isLeft()) {
        return catalogueResult.map((_) => throw StateError('unreachable'));
      }

      // 6b. covers: the archive's set when it has one; otherwise carry the
      // device's covers over (restored rows may still reference them).
      buildRestoredCovers(
        files,
        manifest,
        activeCoversDir: active.coversDir,
        builderCoversDir: builder.coversDir,
      );

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
      await activate(builder);
      builder = null; // now live: never discard it in `finally`

      // --- Phase 8: cross-DB loan integrity over the FFI vault result ---
      final knownBookIds = legacy.books.map((b) => b.id).toSet();
      final knownBorrowerIds = vaultData.borrowers.map((b) => b.id).toSet();
      final dangling = LoanIntegrity.findDangling(
        loans: vaultData.loans,
        knownBookIds: knownBookIds,
        knownBorrowerIds: knownBorrowerIds,
      );

      return right(
        RestoreSummary(
          booksRestored: legacy.books.length,
          wishlistRestored: legacy.wishlist.length,
          borrowersRestored: vaultData.borrowers.length,
          loansRestored: vaultData.loans.length,
          danglingLoans: dangling,
          // M03: a retained vault was freshly checked by the guard; every
          // loan's book identity was preserved by the plan, or we refused.
          existingVaultKept: scope.retainedLoanBookIds != null,
          // M15: cover refs dropped by validation (unsupported hosts).
          coversDropped: legacy.coversDropped,
          // §3.4: parsed + validated, NOT yet applied — the controller adopts
          // the identity and replaces the network rows after this summary's
          // catalogue switch has succeeded.
          restoredIdentity: identity == null
              ? null
              : (id: identity.id, name: identity.name),
          restoredNetwork: network?.rows,
          networkRowsDropped: network?.dropped ?? 0,
          identityInvalid: manifest.hasIdentity && identity == null,
          networkInvalid: manifest.hasNetwork && network == null,
          // W2: the kinds/details join counts. An entry that was DECLARED but
          // unreadable is flagged (everything else restores regardless — the
          // affected rows came back as books, which the counts show).
          kindsApplied: applied.kindsApplied,
          periodicalsRestored: legacy.periodicals.length,
          issuesLinked: applied.issuesLinked,
          issuesDetached: applied.issuesDetached,
          rowsSkippedUnknownKind: applied.rowsSkippedUnknownKind,
          periodicalsDropped: applied.periodicalsDropped,
          itemKindsInvalid: manifest.hasItemKinds && extras.itemKinds == null,
          periodicalsInvalid:
              manifest.hasPeriodicals && extras.periodicals == null,
        ),
      );
    } on _ReplacementRefused catch (e) {
      return left(e.failure);
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
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; nothing actionable.
      }
    }
  }

  /// Snapshots the live catalogue into the builder and replaces its rows.
  Future<Either<Failure, Unit>> _buildCatalogue({
    required DataGeneration active,
    required DataGeneration builder,
    required LegacyCatalogueRows legacy,
    required CatalogueReplacementScope scope,
  }) async {
    // Snapshot through a private read connection so the copy is consistent
    // and independent of whichever executor the app holds on the live file.
    // `VACUUM INTO` refuses to run inside a transaction and refuses to
    // overwrite; the builder directory is fresh, so the target is absent.
    // A device that never opened its catalogue has no file yet: Drift then
    // creates the builder's schema from scratch when opened below.
    if (File(active.catalogueDbPath).existsSync()) {
      final source = sqlite3.open(
        active.catalogueDbPath,
        mode: OpenMode.readOnly,
      );
      try {
        source.execute('VACUUM INTO ?', [builder.catalogueDbPath]);
      } finally {
        source.dispose();
      }
    }

    final db = _openCatalogue(builder.catalogueDbPath);
    try {
      await db.transaction(() async {
        final loanIds = scope.retainedLoanBookIds;
        if (loanIds != null) {
          final local = await db.select(db.books).get();
          final plan = CatalogueReplacementPlan.build(
            local: local.map((row) => row.toDomain()).toList(),
            incoming: legacy.books,
            loanBookIds: loanIds,
          );
          legacy.books = plan.match(
            (failure) => throw _ReplacementRefused(failure),
            (books) => books,
          );
        }
        if (!scope.isCurrent) {
          throw const _ReplacementRefused(CatalogueReplacementScope.cancelled);
        }
        // The books delete cascades to `magazine_issues` (FK, plan A.6); the
        // periodicals table is cleared inside writeRestoredPeriodicals.
        await db.delete(db.books).go();
        await db.delete(db.wishlistBooks).go();
        // W2: row-by-row — the assigned ids key the kind detail rows.
        await insertRestoredItems(db, legacy.books);
        await db.batch((b) {
          for (final w in legacy.wishlist) {
            b.insert(db.wishlistBooks, w.toCompanion());
          }
        });
        // W2: the periodicals write joins this transaction (Drift
        // transactions are zone-scoped); a Left rolls EVERYTHING back —
        // restore never leaves a half-written catalogue.
        final replaced = await writeRestoredPeriodicals(db, legacy.periodicals);
        replaced.match((f) => throw _ReplacementRefused(f), (_) {});
        final reprojected = await reprojectRestoredIssues(db);
        reprojected.match((f) => throw _ReplacementRefused(f), (_) {});
        // Rebuild the derived FTS index from the rows just written.
        await db.rebuildFts();
        if (!scope.isCurrent) {
          throw const _ReplacementRefused(CatalogueReplacementScope.cancelled);
        }
      });
    } finally {
      await db.close();
    }
    return right(unit);
  }

  static String _utf8(Uint8List bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);
}

/// Infrastructure-only rollback signal, converted back to a typed Failure.
final class _ReplacementRefused implements Exception {
  const _ReplacementRefused(this.failure);
  final Failure failure;
}
