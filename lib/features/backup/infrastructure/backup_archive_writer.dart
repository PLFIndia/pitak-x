/// Writes a Pitaka `.pitabak` backup archive (#28B). Pure-Dart port of the
/// Kotlin `BackupArchive` writer, adapted to our split storage:
///  - books / wishlist live in DRIFT here, but the archive format is Room's, so
///    we WRITE fresh Room-compatible `books.db` / `wishlist.db` SQLite files
///    from the current Drift rows (we cannot copy the Drift file);
///  - the encrypted `borrowers.db` + its `backup_blob` already exist on disk
///    (the persistent vault); we copy them VERBATIM (no re-wrap on backup,
///    exactly like Kotlin) when a vault exists;
///  - user cover images are bundled as flat `cover_<leaf>` entries;
///  - a `manifest.json` describes what is present.
///
/// Restore targets (Q-28c, reconfirmed 2026-09-03 — "only this app"): the
/// archives this writer produces are read by PITAK ONLY (Pitak↔Pitak), and
/// Pitak's reader additionally accepts archives the retired Kotlin app made
/// (Kotlin→Pitak). The reverse — the Kotlin app restoring OUR archive — is
/// NOT a goal and is not tested. Consequences you should know before touching
/// this file:
///  - the Room `room_master_table` row + `user_version` below are kept only
///    so the file stays in the same *shape* Kotlin archives have (one reader,
///    one format); they are NOT a promise that Room would accept the file
///    (the version sticker is v9 while the columns are v10-shaped — harmless
///    for our reader, which never looks at either);
///  - we deliberately do NOT emit the FTS4 `books_fts` mirror: the bundled
///    SQLite (`sqlite3_flutter_libs`) ships FTS5 only — `USING FTS4` throws
///    `no such module: fts4` on-device — and our reader rebuilds Drift's own
///    FTS after restore.
///
/// No secrets pass through here: the vault DB is opaque ciphertext on disk and
/// the blob is already ciphertext. This writer never sees the vault key.
///
/// **Where the work runs (N10-c).** Everything heavy — the two SQLite files,
/// every cover read, the packing — happens inside a one-shot worker
/// isolate (`Isolate.run`), so the UI isolate keeps painting while a large
/// backup is assembled. The calling isolate only resolves the cheap, plain
/// facts the worker needs (paths, "is there a vault", the ciphertext blob
/// string) into a [_BackupJob] and ships that across. Two consequences worth
/// knowing before you change this file:
///  - the worker opens SQLite ITSELF (a top-level function in
///    `backup_room_databases.dart`, where the two SQLite files are
///    written). The `sqlite3.open` tear-off cannot be sent to an isolate —
///    it drags a `NativeFinalizer` along and the send fails at runtime — so
///    there is deliberately no `openDatabase` constructor seam any more;
///  - the ZIP is written straight to a FILE (`backup_zip_file.dart`, BR4):
///    one cover is in memory at a time and the databases are read from
///    disk in small pieces, so the memory needed no longer grows with the
///    size of the backup.
///
/// **The files of one build (BR4).** `workDir` belongs to the caller and is
/// used by this one build only. Inside it:
///
/// ```text
/// <workDir>/scratch/                       books.db, wishlist.db, a copy of
///                                          borrowers.db, the unfinished ZIP
/// <workDir>/Pitak-backup-<date>-<time>.pitabak   the finished backup
/// ```
///
/// `scratch/` is created and removed by `build` itself, on every way out.
/// The finished file appears under its final name only as the last step,
/// when the ZIP is complete and not too large. So after a success `workDir`
/// holds exactly that one file, and after a refusal or an error it holds
/// nothing of this build.
///
/// The vault database is COPIED into `scratch/` before anything is packed
/// (`VaultArtifactsStore.snapshotDatabaseTo`). The ZIP is then fed from
/// files nothing else can write, so what the checks measured is what goes
/// in. Copying and renaming are done by other files on purpose: this file
/// names the covers folder, and `cover_files_immutable_test.dart` allows
/// such a file to read only.
///
/// **The writer refuses what the reader refuses (S5, BR3).** Every entry is
/// measured and checked against [BackupLimits] before the ZIP is started
/// (`backup_preflight.dart`), and the finished file is checked once more. A
/// library that does not fit gets a typed refusal with the numbers, never a
/// backup that cannot be restored.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_file_name.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart'
    show
        identityEntryName,
        manifestEntryName,
        networkEntryName,
        publishStateEntryName;
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';
import 'package:pitaka/features/backup/infrastructure/backup_room_databases.dart';
import 'package:pitaka/features/backup/infrastructure/backup_zip_file.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show coverEntryPrefix;
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart'
    show booksDbEntryName, wishlistDbEntryName;
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

// The archive entry names are the restore reader's own constants (imported
// above; the vault pair lives in `backup_entry_bounds.dart`), so the writer,
// the reader and the table of size caps share one set of names.

/// What the worker hands back: the size of the finished file (which lies at
/// the final path the job named) with the titles of the items whose cover
/// was left out, or one refusal. Plain data only.
typedef _BuildOutcome = ({
  int sizeBytes,
  List<String> coversLeftOut,
  BackupRefusal? refusal,
});

/// Everything the worker isolate needs, as plain sendable data (paths,
/// strings, ints, entity lists). No closures, no `ref`, no FFI handles.
///
/// A record type rather than a class: there is nothing to encapsulate, and a
/// record makes it visually obvious at the `Isolate.run` call that only data
/// crosses.
typedef _BackupJob = ({
  List<CatalogueItem> books,
  List<WishlistBook> wishlist,
  List<Periodical> periodicals,
  String scratchDir,
  String finalPath,
  int exportedAt,
  bool hasVault,
  String? vaultCopyPath,
  String? blob,
  String coversDir,
  String? identityJson,
  String? networkJson,
  String? publishStateJson,
  BackupLimits limits,
});

/// Builds a `.pitabak` archive as a file.
class BackupArchiveWriter implements BackupArchiveBuilder {
  /// Creates the writer.
  ///
  /// [vaultStore] locates the persistent vault artifacts; [coversDir] is where
  /// user cover images live. [limits] is what one backup can hold; the app
  /// uses the default, tests pass small limits.
  const BackupArchiveWriter({
    required this.vaultStore,
    required this.coversDir,
    this.limits = BackupLimits.current,
  });

  /// Persistent vault locations (DB + blob), copied verbatim when present.
  final VaultArtifactsStore vaultStore;

  /// Directory holding user cover images (`covers/<leaf>`).
  final String coversDir;

  /// What one backup can hold (BR3). The reader's caps are built from the
  /// same value, so what this writer accepts, the reader accepts.
  final BackupLimits limits;

  /// Folder inside `workDir` for everything that is thrown away again.
  static const String _scratchDirName = 'scratch';

  /// Name of the ZIP while it is being written (inside the scratch folder).
  static const String _unfinishedZipName = 'backup.part';

  /// Builds the archive file from [books] + [wishlist] + [periodicals],
  /// including the vault and covers when present. [exportedAt] stamps the
  /// manifest (epoch millis) and names the file. [workDir] belongs to the
  /// caller; see the library doc for what this build puts into it and what
  /// it leaves there.
  ///
  /// The heavy lifting runs in a worker isolate (see the library doc). The
  /// vault facts are read HERE, on the calling isolate, because
  /// [VaultArtifactsStore] is an interface whose implementation is not
  /// guaranteed sendable; they are two `existsSync` calls, a tiny file read
  /// (the blob is ciphertext that already lives as a plain file) and the
  /// copy of the vault database, which `dart:io` does off this isolate.
  @override
  Future<Either<Failure, BuiltBackup>> build({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required List<Periodical> periodicals,
    required String workDir,
    required int exportedAt,
    required String? identityJson,
    required String? networkJson,
    required String? publishStateJson,
  }) async {
    final scratch = Directory(p.join(workDir, _scratchDirName));
    // The name is made from the manifest's time and nothing else, so no
    // text from outside becomes part of a path (see `backup_file_name.dart`).
    final finalPath = p.join(
      workDir,
      backupFileName(DateTime.fromMillisecondsSinceEpoch(exportedAt)),
    );
    try {
      // Fresh on purpose: nothing of an earlier build may slip into this one.
      if (scratch.existsSync()) await scratch.delete(recursive: true);
      await scratch.create(recursive: true);

      final hasVault = vaultStore.isInitialized();
      final vaultCopyPath = hasVault
          ? p.join(scratch.path, borrowersDbEntryName)
          : null;
      if (vaultCopyPath != null) {
        await vaultStore.snapshotDatabaseTo(vaultCopyPath);
      }
      final outcome = await _runWorker((
        books: books,
        wishlist: wishlist,
        periodicals: periodicals,
        scratchDir: scratch.path,
        finalPath: finalPath,
        exportedAt: exportedAt,
        hasVault: hasVault,
        vaultCopyPath: vaultCopyPath,
        blob: hasVault ? vaultStore.readBlob() : null,
        coversDir: coversDir,
        identityJson: identityJson,
        networkJson: networkJson,
        publishStateJson: publishStateJson,
        limits: limits,
      ));
      return _toEither(outcome, finalPath);
    } finally {
      // On EVERY way out: success, refusal, or an error on either isolate.
      // If this removal itself fails, the build fails with it and the
      // caller discards the whole `workDir`.
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    }
  }

  /// Starts the worker isolate for [job] and waits for its outcome.
  ///
  /// A function of its own ON PURPOSE (beginner note): the little function
  /// handed to `Isolate.run` is copied to the other isolate together with
  /// every variable it can see. Here it can see [job] and nothing else, so
  /// nothing that cannot be copied (a `Directory`, the vault store) can
  /// ever be dragged along by a later change to `build`.
  static Future<_BuildOutcome> _runWorker(_BackupJob job) =>
      Isolate.run(() => _buildInWorker(job), debugName: 'pitaka-backup-build');

  /// Maps the worker's plain outcome to the typed result ON THIS ISOLATE —
  /// no [Failure] object ever crosses the boundary (S5).
  static Either<Failure, BuiltBackup> _toEither(
    _BuildOutcome outcome,
    String finalPath,
  ) {
    final refusal = outcome.refusal;
    if (refusal != null) {
      return left(
        BackupTooLargeFailure(refusal.code.name, refusal.actual, refusal.limit),
      );
    }
    return right(
      BuiltBackup(
        path: finalPath,
        sizeBytes: outcome.sizeBytes,
        coversLeftOut: outcome.coversLeftOut,
      ),
    );
  }

  static _BuildOutcome _refused(BackupRefusal refusal) =>
      (sizeBytes: 0, coversLeftOut: const [], refusal: refusal);

  /// The whole build, run inside the worker isolate. Static so it cannot
  /// accidentally capture `this` (and with it the non-sendable store).
  static _BuildOutcome _buildInWorker(_BackupJob job) {
    // ADR 0014 W2: kinds are EXPLICIT because books.db is Room-shaped and
    // cannot say them. Both entries are omitted (flags false) when there is
    // nothing to say — a books-only library keeps the archive it always had.
    final hasKinds = job.books.any(
      (b) =>
          b.kind != ItemKind.book &&
          b.itemUid != null &&
          b.itemUid!.trim().isNotEmpty,
    );
    final hasIssues = job.books.any(
      (b) =>
          b.details is IssueOf &&
          b.itemUid != null &&
          b.itemUid!.trim().isNotEmpty,
    );
    final itemKindsJson = hasKinds
        ? ItemDetailsArchiveCodec.encodeItemKinds(job.books)
        : null;
    final periodicalsJson = job.periodicals.isNotEmpty || hasIssues
        ? ItemDetailsArchiveCodec.encodePeriodicals(job.periodicals, job.books)
        : null;

    // S5 (L5): refuse to emit an archive the restore reader would reject or
    // downgrade. The bounds are the READER's own constants, so writer and
    // reader cannot drift apart. This runs FIRST — pure in-memory work — so an
    // oversized catalogue is refused before the worker writes a single file.
    if (itemKindsJson != null) {
      final refusal = overflowOf(
        json: itemKindsJson,
        rows: itemKindRowCount(job.books),
        tooLarge: BackupOverflow.itemKindsTooLarge,
        tooManyRows: BackupOverflow.itemKindsTooManyRows,
      );
      if (refusal != null) return _refused(refusal);
    }
    if (periodicalsJson != null) {
      final refusal = overflowOf(
        json: periodicalsJson,
        rows: periodicalEntryRowCount(job.periodicals, job.books),
        tooLarge: BackupOverflow.periodicalsTooLarge,
        tooManyRows: BackupOverflow.periodicalsTooManyRows,
      );
      if (refusal != null) return _refused(refusal);
    }

    final booksDbPath = p.join(job.scratchDir, booksDbEntryName);
    final wishlistDbPath = p.join(job.scratchDir, wishlistDbEntryName);
    writeRoomBooksDb(booksDbPath, job.books);
    writeRoomWishlistDb(wishlistDbPath, job.wishlist);

    // BR3 (D10): a cover larger than the reader's cap is left out and its
    // item named. Only sizes are looked at here; no cover is opened yet.
    final covers = selectBackupCovers(
      files: _coverFiles(job.coversDir),
      maxCoverBytes: job.limits.maxCoverBytes,
      books: job.books,
      wishlist: job.wishlist,
      periodicals: job.periodicals,
    );
    final blob = job.hasVault ? job.blob : null;

    final manifest = BackupManifest(
      exportedAt: job.exportedAt,
      hasBorrowers: job.hasVault,
      hasBackupBlob: blob != null,
      hasCovers: covers.kept.isNotEmpty,
      hasIdentity: job.identityJson != null,
      hasNetwork: job.networkJson != null,
      hasItemKinds: itemKindsJson != null,
      hasPeriodicals: periodicalsJson != null,
      hasPublishState: job.publishStateJson != null,
    );

    // Every entry, in archive order, measured but not yet read. The JSON
    // entries are plain text in the clear (the documented honest limit of
    // the format — README › Backup); `publish_state.json` never holds a
    // token (the caller's codec has none).
    final entries = <PlannedBackupEntry>[
      _text(manifestEntryName, manifest.toJson()),
      _database(booksDbEntryName, booksDbPath),
      _database(wishlistDbEntryName, wishlistDbPath),
      if (job.vaultCopyPath case final path?)
        _database(borrowersDbEntryName, path),
      if (blob != null) _text(backupBlobEntryName, blob),
      for (final cover in covers.kept)
        _cover(
          coverEntryPrefix + cover.leaf,
          p.join(job.coversDir, cover.leaf),
          cover.bytes,
        ),
      if (job.identityJson case final json?) _text(identityEntryName, json),
      if (job.networkJson case final json?) _text(networkEntryName, json),
      if (itemKindsJson != null) _text(itemKindsEntryName, itemKindsJson),
      if (periodicalsJson != null) _text(periodicalsEntryName, periodicalsJson),
      if (job.publishStateJson case final json?)
        _text(publishStateEntryName, json),
    ];

    // BR3 pre-flight: refuse what the reader would refuse to open, BEFORE
    // the ZIP is started and before a single cover is read.
    final refusal = backupRefusalFor(entries, job.limits);
    if (refusal != null) return _refused(refusal);

    // BR4: the ZIP goes straight to a file in the scratch folder and gets
    // its final name only when it is complete (`backup_zip_file.dart`). A
    // file is read only when its turn comes, and the build fails as a whole
    // if it is no longer the size the pre-flight judged.
    final packed = packBackupZip(
      entries: entries,
      partPath: p.join(job.scratchDir, _unfinishedZipName),
      finalPath: job.finalPath,
      maxArchiveBytes: job.limits.maxArchiveBytes,
    );
    if (!packed.inPlace) {
      return _refused((
        code: BackupOverflow.archiveTooLarge,
        actual: packed.sizeBytes,
        limit: job.limits.maxArchiveBytes,
      ));
    }
    return (
      sizeBytes: packed.sizeBytes,
      coversLeftOut: covers.leftOutTitles,
      refusal: null,
    );
  }

  /// Cover files under [coversDir] with their sizes, sorted by name; empty
  /// when none. Only the folder listing is read: no cover is opened.
  static List<CoverFileSize> _coverFiles(String coversDir) {
    final dir = Directory(coversDir);
    if (!dir.existsSync()) return const [];
    return [
      for (final file in dir.listSync().whereType<File>())
        (leaf: p.basename(file.path), bytes: file.lengthSync()),
    ]..sort((a, b) => a.leaf.compareTo(b.leaf));
  }

  /// A text entry: already in memory, so its size is exact.
  static PlannedBackupEntry _text(String name, String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return PlannedBackupEntry(name, bytes.length, () => bytes);
  }

  /// A cover picture: [bytes] is its size from the folder listing. The file
  /// is read whole, but only when its turn in the ZIP comes.
  static PlannedBackupEntry _cover(String name, String path, int bytes) =>
      PlannedBackupEntry(name, bytes, File(path).readAsBytesSync);

  /// A database file in the scratch folder: measured now, and later fed to
  /// the ZIP from disk in small pieces (never read whole).
  static PlannedBackupEntry _database(String name, String path) =>
      PlannedBackupEntry.streamed(name, File(path).lengthSync(), path);
}
