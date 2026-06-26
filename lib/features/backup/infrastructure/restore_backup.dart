/// Applies a Pitaka backup archive to this device (PLAN.md Step 7, the crux).
///
/// Restore is an AUTHORITATIVE OVERWRITE of local state, not an additive merge
/// (mirrors Kotlin `BackupRestore`). Ordering is fail-closed: everything that
/// can fail without side effects (extract, manifest, blob unwrap) happens
/// BEFORE any device write. Then the library/wishlist are replaced inside a
/// single Drift transaction; covers are routed; cross-DB loan integrity is
/// checked.
///
/// Trust boundary: the encrypted `borrowers.db` + vault key live entirely in
/// the Rust core (via [VaultRepository]); the plain `books.db`/`wishlist.db`
/// are read here with `sqlite3` (no secrets). The vault key never reaches Dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/infrastructure/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/book_mapper.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/wishlist_mapper.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// ZIP entry names inside a Pitaka backup archive.
const String _manifestEntry = 'manifest.json';
const String _booksDbEntry = 'books.db';
const String _wishlistDbEntry = 'wishlist.db';
const String _borrowersDbEntry = 'borrowers.db';
const String _backupBlobEntry = 'backup_blob';
const String _coverEntryPrefix = 'cover_';

/// Opens a plain SQLite database file read-only. Injectable for tests.
typedef LegacyDbOpener = CommonDatabase Function(String path);

CommonDatabase _defaultOpen(String path) =>
    sqlite3.open(path, mode: OpenMode.readOnly);

/// Restores a backup archive into the app's Drift DB + Rust vault.
final class RestoreBackup {
  /// Creates the restorer.
  ///
  /// [db] is the live app database; [vault] reads the encrypted borrowers DB
  /// through the Rust core; [coversDir] is where `cover_*` entries are written
  /// (wiped first — restore replaces device state); [workDir] is a scratch dir
  /// for extracted files; [openLegacyDb] is injectable for tests.
  RestoreBackup({
    required this.db,
    required this.vault,
    required this.coversDir,
    required this.workDir,
    LegacyDbOpener openLegacyDb = _defaultOpen,
  }) : _open = openLegacyDb;

  /// The live application database (books + wishlist).
  final AppDatabase db;

  /// Vault reader over the Rust FFI core.
  final VaultRepository vault;

  /// Absolute path of the covers directory (`<appDocs>/covers`).
  final String coversDir;

  /// Absolute path of a scratch directory for extracted files.
  final String workDir;

  final LegacyDbOpener _open;

  /// Applies [archiveBytes], unlocking the vault with [passphrase]. The caller
  /// owns [passphrase] and must dispose it.
  ///
  /// Returns a typed [Failure] on any problem, with no partial device writes on
  /// a pre-write failure (extract/manifest/blob). Wrong passphrase is distinct
  /// from a corrupt archive.
  Future<Either<Failure, RestoreSummary>> restore({
    required Uint8List archiveBytes,
    required SecretBytes passphrase,
  }) async {
    // --- Phase 1: extract (no device writes yet) ---
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(archiveBytes);
    } on BoundedExtractionException catch (e) {
      return left(BackupCorruptFailure(e.message));
    }

    // --- Phase 2: manifest, refuse schemaVersion > known ---
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

    // --- Phase 3: stage files to disk (sqlite3 + FFI need paths) ---
    final Directory work;
    try {
      work = Directory(workDir);
      if (work.existsSync()) work.deleteSync(recursive: true);
      work.createSync(recursive: true);
    } on FileSystemException catch (e) {
      return left(StorageFailure('Could not create work dir: ${e.message}'));
    }

    try {
      // --- Phase 4: vault unlock (no device writes yet; fail closed) ---
      var vaultData = VaultData.empty;
      if (manifest.hasBackupBlob) {
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
        final borrowersPath = _stage(work, _borrowersDbEntry, borrowersBytes);
        final unlocked = await vault.unlockAndRead(
          passphrase: passphrase,
          blob: _utf8(blobBytes).trim(),
          dbPath: borrowersPath,
        );
        // A wrong passphrase / corrupt vault aborts BEFORE any device write.
        final early = unlocked.match<Failure?>((f) => f, (data) {
          vaultData = data;
          return null;
        });
        if (early != null) return left(early);
      }

      // --- Phase 5: read legacy books/wishlist (still no device writes) ---
      final readResult = _readLegacy(work, files, manifest);
      if (readResult.isLeft()) {
        return readResult.match(left, (_) => throw StateError('unreachable'));
      }
      final legacy = readResult.getOrElse(
        (_) => throw StateError('unreachable'),
      );

      // --- Phase 6: authoritative overwrite inside one transaction ---
      try {
        await db.transaction(() async {
          await db.delete(db.books).go();
          await db.delete(db.wishlistBooks).go();
          await db.batch((b) {
            for (final book in legacy.books) {
              b.insert(db.books, book.toCompanion());
            }
            for (final w in legacy.wishlist) {
              b.insert(db.wishlistBooks, w.toCompanion());
            }
          });
        });
        await db.rebuildFts();
      } on Object catch (e) {
        return left(StorageFailure('restore transaction failed: $e'));
      }

      // --- Phase 7: route covers (best-effort, wipe-first) ---
      if (manifest.hasCovers) {
        _restoreCovers(files);
      }

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
        ),
      );
    } finally {
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; nothing actionable.
      }
    }
  }

  Either<Failure, _LegacyRows> _readLegacy(
    Directory work,
    Map<String, Uint8List> files,
    BackupManifest manifest,
  ) {
    final rows = _LegacyRows();
    if (manifest.hasBooks) {
      final bytes = files[_booksDbEntry];
      if (bytes == null) {
        return left(const BackupCorruptFailure('Archive missing books.db'));
      }
      final path = _stage(work, _booksDbEntry, bytes);
      final readResult = _withDb(path, (db) => LegacyDbReader(db).readBooks());
      if (readResult.isLeft()) {
        return readResult.match(left, (_) => throw StateError('unreachable'));
      }
      rows.books = readResult.getOrElse((_) => const []);
    }
    if (manifest.hasWishlist) {
      final bytes = files[_wishlistDbEntry];
      if (bytes == null) {
        return left(const BackupCorruptFailure('Archive missing wishlist.db'));
      }
      final path = _stage(work, _wishlistDbEntry, bytes);
      final readResult = _withDb(
        path,
        (db) => LegacyDbReader(db).readWishlist(),
      );
      if (readResult.isLeft()) {
        return readResult.match(left, (_) => throw StateError('unreachable'));
      }
      rows.wishlist = readResult.getOrElse((_) => const []);
    }
    return right(rows);
  }

  Either<Failure, T> _withDb<T>(
    String path,
    T Function(CommonDatabase) action,
  ) {
    CommonDatabase? handle;
    try {
      handle = _open(path);
      return right(action(handle));
    } on Object catch (e) {
      return left(BackupCorruptFailure('Could not read legacy DB: $e'));
    } finally {
      handle?.dispose();
    }
  }

  String _stage(Directory work, String name, Uint8List bytes) {
    final path = p.join(work.path, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  void _restoreCovers(Map<String, Uint8List> files) {
    // Restore replaces device state: wipe the covers dir first so no cover
    // from the pre-restore library survives.
    final dir = Directory(coversDir);
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
    } on FileSystemException {
      return; // best-effort; a missing cover just renders a placeholder
    }
    for (final entry in files.entries) {
      if (!entry.key.startsWith(_coverEntryPrefix)) continue;
      final leaf = entry.key.substring(_coverEntryPrefix.length);
      // Defence in depth: re-validate via CoverPaths.
      if (CoverPaths.leafOf('${CoverPaths.prefix}$leaf') != leaf) continue;
      try {
        File(p.join(coversDir, leaf)).writeAsBytesSync(entry.value);
      } on FileSystemException {
        continue; // best-effort per cover
      }
    }
  }

  static String _utf8(Uint8List bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);
}

/// Internal carrier for rows read out of the legacy DBs.
class _LegacyRows {
  List<Book> books = const [];
  List<WishlistBook> wishlist = const [];
}
