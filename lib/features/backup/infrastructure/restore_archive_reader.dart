/// Reads the parts of a backup from its FILE, in a worker isolate (backup
/// infrastructure; backup rework BR6, the memory half of review finding
/// P3-B3).
///
/// WHY THIS FILE EXISTS (beginner note): a restore used to unpack the whole
/// backup into memory, twice, on the screen's own thread. A backup with
/// thousands of cover pictures needs more memory than a phone gives an app,
/// and the screen froze meanwhile. This file takes from the archive only
/// what the next step needs:
///
///  - the small text entries (the manifest, and what the manifest
///    announces), into memory, each under its own cap;
///  - the three databases, straight into files of the caller's work folder;
///  - of the cover pictures only their NAMES. The pictures themselves are
///    unpacked later, one by one, straight into the new data generation
///    (`restore_covers_builder.dart`).
///
/// It runs in a worker isolate (`Isolate.run`), so the screen keeps
/// painting. Two isolates share no memory: the worker gets a small record
/// of plain data (a path, the limits, a folder) and hands back a record of
/// plain data. No `Failure` object crosses that border, the same rule the
/// backup writer keeps: a refusal travels as its text, trouble with the
/// disk as a code, and the restorer turns both into typed failures.
///
/// WHAT IS NEVER UNPACKED: an entry the manifest does not announce, an
/// entry above its cap, and every name this app does not write. That
/// includes `books.db-wal` and its kind: a file meant to sit next to a
/// database is ignored by the reader, and the only names ever written here
/// are the three fixed ones below, into a folder that was empty.
///
/// The rules for the archive itself (sizes, names, checksums) are not here:
/// `BoundedZipFile` checks everything the file declares when it is opened,
/// and holds every entry to its declared size and checksum when it is
/// taken. The rule per entry name is `backupEntryRule`, the table the
/// writer checks against.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show restorableCoverLeaf;
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart'
    show booksDbEntryName, wishlistDbEntryName;
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

/// What the worker is asked to do. Plain data only: this record is copied
/// to the worker isolate.
///
///  - `archivePath`: the backup file. It is only read, never written and
///    never deleted;
///  - `limits`: what one backup may hold (the app passes
///    `BackupLimits.current`, tests pass small ones);
///  - `workDir`: an EMPTY folder of the caller's for the databases, or null
///    for an inspection, which needs no database and stages none.
typedef RestoreReadJob = ({
  String archivePath,
  BackupLimits limits,
  String? workDir,
});

/// Trouble with the disk during a restore, as a code (a `Failure` object
/// does not cross the isolate border; the restorer makes one from this).
/// Shared by the two workers of a restore: this one, and the one that
/// writes the cover pictures.
enum RestoreDiskTrouble {
  /// The backup file could not be opened or read: it is gone, or the
  /// system took it away.
  archiveUnreadable,

  /// A file of the restore could not be written (for example: no free
  /// storage).
  targetUnwritable,
}

/// Which trouble the exception [e] stands for, in a worker that reads the
/// backup at [archivePath]. A `FileSystemException` names the file it is
/// about: the archive, or a file the worker was writing.
RestoreDiskTrouble restoreDiskTroubleOf(
  FileSystemException e, {
  required String archivePath,
}) => e.path == archivePath
    ? RestoreDiskTrouble.archiveUnreadable
    : RestoreDiskTrouble.targetUnwritable;

/// Opens the backup at [archivePath] under the rules of a backup with
/// [limits], for taking entries one at a time.
///
/// The ONE place a restore opens its archive, so that every look at the
/// file applies the same rules: the caps of [limits] for the archive as a
/// whole, and `backupEntryRule` for each entry name. Every rule on what
/// the file DECLARES runs here, before a byte of content is unpacked.
///
/// [unpackedBytesProbe] is the reader's test seam (see `BoundedZipFile`).
/// The caller closes the file. Throws what `BoundedZipFile.open` throws.
BoundedZipFile openBackupArchive(
  String archivePath,
  BackupLimits limits, {
  void Function(int unpackedBytes)? unpackedBytesProbe,
}) => BoundedZipFile.open(
  archivePath,
  limits: ZipLimits.forBackup(limits),
  policy: (name) => backupEntryRule(name, limits),
  unpackedBytesProbe: unpackedBytesProbe,
);

/// The cover pictures of the open backup [zip], by file name and in
/// archive order: those a restore writes (`toWrite`) and those above their
/// cap, which it leaves out (`leftOut`, decision D18).
///
/// Looks at the entry list only; nothing is unpacked. An entry is a cover
/// when `restorableCoverLeaf` says so. A cover entry with a name that rule
/// refuses is in neither list: it is never written, and no item can refer
/// to it.
///
/// Both workers of a restore call this, so the covers that are listed
/// first and the covers that are written later are found by one rule.
({List<String> toWrite, List<String> leftOut}) listBackupCovers(
  BoundedZipFile zip,
) {
  final toWrite = <String>[];
  final leftOut = <String>[];
  for (final entry in zip.entries) {
    final leaf = restorableCoverLeaf(entry.name);
    if (leaf == null) continue;
    switch (entry.verdict) {
      case ZipEntryVerdict.take:
        toWrite.add(leaf);
      case ZipEntryVerdict.leftOut:
        leftOut.add(leaf);
      case ZipEntryVerdict.ignored:
        // A cover name always has a rule; nothing to do.
        break;
    }
  }
  return (toWrite: toWrite, leftOut: leftOut);
}

/// What the worker hands back. Plain data only.
///
///  - `entries`: the small entries that were taken, by entry name. Always
///    the manifest when the archive has one; then only what the manifest
///    announces. An entry that is missing, or above its cap, is simply not
///    in the map;
///  - `booksDbPath`, `wishlistDbPath`, `borrowersDbPath`: where each
///    database was staged, or null when it was not (an inspection, an entry
///    the manifest does not announce, an entry the archive lacks);
///  - `coversToWrite`: the file names of the cover pictures the restore
///    will write, in archive order. Nothing of them is unpacked yet;
///  - `coversLeftOut`: the file names of the cover pictures that are above
///    their cap and will NOT be restored (decision D18);
///  - `refusal`: why the archive was refused as damaged or hostile, or
///    null;
///  - `trouble`: what went wrong with the disk, or null.
///
/// When `refusal` or `trouble` is set, everything else is empty and no
/// staged file is left behind.
typedef RestoreArchiveParts = ({
  Map<String, Uint8List> entries,
  String? booksDbPath,
  String? wishlistDbPath,
  String? borrowersDbPath,
  List<String> coversToWrite,
  List<String> coversLeftOut,
  String? refusal,
  RestoreDiskTrouble? trouble,
});

/// Runs [readRestoreArchive] for [job] in a worker isolate and waits for
/// its answer.
///
/// A function of its own ON PURPOSE (beginner note): the little function
/// handed to `Isolate.run` is copied to the other isolate together with
/// every variable it can see. Here it can see [job] and nothing else, so
/// nothing that cannot be copied can be dragged along by a later change to
/// the caller.
Future<RestoreArchiveParts> readRestoreArchiveInWorker(RestoreReadJob job) =>
    Isolate.run(
      () => readRestoreArchive(job),
      debugName: 'pitaka-restore-read',
    );

/// The databases a restore stages, by entry name, each with the question
/// "does the manifest announce it". `borrowers.db` goes with the key blob:
/// the vault is restored only as that pair.
const List<(String, bool Function(BackupManifest))> _stagedDatabases = [
  (booksDbEntryName, _hasBooks),
  (wishlistDbEntryName, _hasWishlist),
  (borrowersDbEntryName, _hasVault),
];

bool _hasBooks(BackupManifest manifest) => manifest.hasBooks;
bool _hasWishlist(BackupManifest manifest) => manifest.hasWishlist;
bool _hasVault(BackupManifest manifest) => manifest.hasBackupBlob;

/// The additive entries an inspection shows. A restore takes every entry
/// the manifest announces; an inspection only these two.
const Set<String> _inspectedExtras = {identityEntryName, publishStateEntryName};

/// The work of the worker: opens the archive of [job], checks it, and takes
/// the parts the library doc lists. Synchronous; the app calls it through
/// [readRestoreArchiveInWorker].
///
/// [unpackedBytesProbe] is the reader's test seam, passed through to
/// `BoundedZipFile.open`: it is called once for every entry that is
/// unpacked, so a test can prove what was NOT unpacked.
///
/// Never throws for a bad archive or for trouble with the disk: both come
/// back in the answer.
RestoreArchiveParts readRestoreArchive(
  RestoreReadJob job, {
  void Function(int unpackedBytes)? unpackedBytesProbe,
}) {
  final staged = <String, String>{};
  BoundedZipFile? zip;
  try {
    zip = openBackupArchive(
      job.archivePath,
      job.limits,
      unpackedBytesProbe: unpackedBytesProbe,
    );
    return _take(zip, job, staged);
  } on BoundedExtractionException catch (e) {
    _removeStaged(staged);
    return _stopped(refusal: e.message);
  } on FileSystemException catch (e) {
    _removeStaged(staged);
    return _stopped(
      trouble: restoreDiskTroubleOf(e, archivePath: job.archivePath),
    );
  } finally {
    zip?.close();
  }
}

/// Takes the parts from the open archive. [staged] collects the files
/// written so far, so the caller can remove them when a later step fails.
RestoreArchiveParts _take(
  BoundedZipFile zip,
  RestoreReadJob job,
  Map<String, String> staged,
) {
  final entries = <String, Uint8List>{};

  /// Reads the entry called [name] into [entries] when the archive has it
  /// and it may be taken. An entry above its cap has the verdict "left
  /// out": it is not handed over, and the restore reports it as unreadable.
  void takeIntoMemory(String name) {
    final entry = zip.entry(name);
    final cap = backupEntryCap(name, job.limits);
    if (entry == null || cap == null) return;
    if (entry.verdict != ZipEntryVerdict.take) return;
    entries[name] = zip.read(entry, maxBytes: cap);
  }

  takeIntoMemory(manifestEntryName);
  // Without a manifest this build can use, nothing else is taken. The
  // restorer parses the same bytes again and names the reason.
  final manifest = parseBackupManifest(entries).toNullable();
  if (manifest == null) return _parts(entries: entries);

  final workDir = job.workDir;
  final isInspection = workDir == null;
  for (final name in announcedExtraEntries(manifest)) {
    if (isInspection && !_inspectedExtras.contains(name)) continue;
    takeIntoMemory(name);
  }
  if (!isInspection) {
    if (manifest.hasBackupBlob) takeIntoMemory(backupBlobEntryName);
    for (final (name, isAnnounced) in _stagedDatabases) {
      final entry = zip.entry(name);
      if (entry == null || !isAnnounced(manifest)) continue;
      // The file name is OURS (one of three constants), never the
      // archive's. `writeTo` refuses an existing file and removes its own
      // half-written one.
      final path = p.join(workDir, name);
      zip.writeTo(entry, path);
      staged[name] = path;
    }
  }

  // The cover pictures: names only, from the entry list.
  final covers = manifest.hasCovers
      ? listBackupCovers(zip)
      : (toWrite: const <String>[], leftOut: const <String>[]);
  return _parts(
    entries: entries,
    booksDbPath: staged[booksDbEntryName],
    wishlistDbPath: staged[wishlistDbEntryName],
    borrowersDbPath: staged[borrowersDbEntryName],
    coversToWrite: covers.toWrite,
    coversLeftOut: covers.leftOut,
  );
}

RestoreArchiveParts _parts({
  Map<String, Uint8List> entries = const {},
  String? booksDbPath,
  String? wishlistDbPath,
  String? borrowersDbPath,
  List<String> coversToWrite = const [],
  List<String> coversLeftOut = const [],
  String? refusal,
  RestoreDiskTrouble? trouble,
}) => (
  entries: entries,
  booksDbPath: booksDbPath,
  wishlistDbPath: wishlistDbPath,
  borrowersDbPath: borrowersDbPath,
  coversToWrite: coversToWrite,
  coversLeftOut: coversLeftOut,
  refusal: refusal,
  trouble: trouble,
);

/// The answer of a worker that stopped: nothing but the reason.
RestoreArchiveParts _stopped({String? refusal, RestoreDiskTrouble? trouble}) =>
    _parts(refusal: refusal, trouble: trouble);

/// Removes the databases staged so far. Best-effort: the caller discards
/// its whole work folder after a failure anyway.
void _removeStaged(Map<String, String> staged) {
  for (final path in staged.values) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // The work folder goes as a whole.
    }
  }
}
