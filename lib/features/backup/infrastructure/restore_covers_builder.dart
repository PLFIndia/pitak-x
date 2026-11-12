/// Writes the covers folder of the new data generation during a restore
/// (infrastructure): phase 6b of the pipeline in `restore_backup.dart`.
///
/// WHY THIS FILE LOOKS THE WAY IT DOES (beginner note): a backup can hold
/// thousands of cover pictures. Until the streamed restore (backup rework
/// BR6) all of them were unpacked into memory first and written from
/// there, on the screen's own thread. Now each picture goes from the
/// archive file straight into its own file, one at a time, in a worker
/// isolate (`Isolate.run`), and the running count travels back so the page
/// can say "Cover 1,234 of 9,000".
///
/// This is the ONE file of a restore that writes into a covers folder, and
/// it writes only into the folder of the generation that is being BUILT,
/// never into the live one. Two cases:
///
///  - the backup carries covers: the archive is opened again and exactly
///    the covers the first look listed are written. If the list no longer
///    fits the file, the file changed in between and the step refuses;
///  - the backup carries none: the phone's own covers are copied into the
///    new generation, because the restored items may still refer to them.
///
/// Either way a failure leaves the step unfinished and says so; the
/// restorer then discards the whole generation that was being built, so
/// there is no reason to accept a partial set.
///
/// As with the other worker of a restore (`restore_archive_reader.dart`),
/// only plain data crosses the isolate border: a refusal travels as its
/// text, trouble with the disk as a code.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_progress_port.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';

/// Zip entry prefix for bundled cover images (restore-reader contract).
const String coverEntryPrefix = 'cover_';

/// The file name the archive entry [entryName] is restored under, or null
/// when it is not a cover picture this app would write.
///
/// THE ONE RULE for "is this entry a cover, and what is its file called"
/// (backup rework BR6). Whoever lists the covers of an archive asks here,
/// so the covers that are written and the covers the publishing record
/// believes in can never be two different sets.
///
/// The entry must be called `cover_<name>`, and `<name>` must be a file
/// name [CoverPaths.leafOf] accepts unchanged: not empty, no `..`, no `/`,
/// no `:`, and nothing that trimming would alter. That is the zip-slip and
/// path-trick defence, and it is the same rule an item's cover reference
/// has to pass, so no item can ever point at a file this refuses.
String? restorableCoverLeaf(String entryName) {
  if (!entryName.startsWith(coverEntryPrefix)) return null;
  final leaf = entryName.substring(coverEntryPrefix.length);
  return CoverPaths.leafOf('${CoverPaths.prefix}$leaf') == leaf ? leaf : null;
}

/// What the worker is asked to do. Plain data only: this record is copied
/// to the worker isolate.
///
///  - `archivePath`: the backup file. Only read;
///  - `limits`: what one backup may hold, the same value the first look
///    used;
///  - `coversToWrite`: the file names the first look listed
///    (`RestoreArchiveParts.coversToWrite`), or null when the backup
///    carries no covers and the phone's own are carried over;
///  - `activeCoversDir`: the covers folder of the live generation. Only
///    read, and only when covers are carried over;
///  - `builderCoversDir`: the covers folder of the generation being built.
///    The only folder written;
///  - `progressPort`: where the running count goes, or null when nobody
///    listens.
typedef RestoreCoversJob = ({
  String archivePath,
  BackupLimits limits,
  List<String>? coversToWrite,
  String activeCoversDir,
  String builderCoversDir,
  SendPort? progressPort,
});

/// What the worker hands back: nothing when every cover is in place, or
/// why it stopped (`refusal`: the archive is not what the first look saw,
/// or an entry is damaged; `trouble`: the disk).
typedef RestoreCoversAnswer = ({String? refusal, RestoreDiskTrouble? trouble});

/// Why the step refuses when the covers of the archive are no longer the
/// ones the first look listed. Names no file: the text ends up in a
/// failure.
const String _archiveChanged =
    'The backup file changed while it was being restored';

/// Runs [buildRestoredCovers] for [job] in a worker isolate and waits for
/// its answer.
///
/// A function of its own ON PURPOSE (beginner note): the little function
/// handed to `Isolate.run` is copied to the other isolate together with
/// every variable it can see. Here it can see [job] and nothing else.
Future<RestoreCoversAnswer> buildRestoredCoversInWorker(RestoreCoversJob job) =>
    Isolate.run(
      () => buildRestoredCovers(job),
      debugName: 'pitaka-restore-covers',
    );

/// The work of the worker: fills the covers folder of the generation that
/// is being built, as the library doc says. Synchronous; the app calls it
/// through [buildRestoredCoversInWorker].
///
/// [onCoverWritten] receives the running count after EVERY cover. Without
/// it the count goes to the job's port, thinned out to a few reports a
/// second (`BackupProgressReporter`); tests pass their own to see every
/// count. [unpackedBytesProbe] is the reader's test seam.
///
/// Never throws for a bad archive or for trouble with the disk: both come
/// back in the answer.
RestoreCoversAnswer buildRestoredCovers(
  RestoreCoversJob job, {
  void Function(int coversDone, int coversTotal)? onCoverWritten,
  void Function(int unpackedBytes)? unpackedBytesProbe,
}) {
  final port = job.progressPort;
  final report =
      onCoverWritten ??
      (port == null ? null : BackupProgressReporter.toPort(port).coverPacked);
  try {
    final target = Directory(job.builderCoversDir)..createSync(recursive: true);
    final listed = job.coversToWrite;
    if (listed == null) {
      _carryOver(Directory(job.activeCoversDir), target, report);
    } else {
      _writeListed(job, listed, target, report, unpackedBytesProbe);
    }
    return (refusal: null, trouble: null);
  } on BoundedExtractionException catch (e) {
    return (refusal: e.message, trouble: null);
  } on FileSystemException catch (e) {
    return (
      refusal: null,
      trouble: restoreDiskTroubleOf(e, archivePath: job.archivePath),
    );
  }
}

/// Writes the covers of the archive, each straight from the archive file
/// into its own new file under [target].
void _writeListed(
  RestoreCoversJob job,
  List<String> listed,
  Directory target,
  void Function(int coversDone, int coversTotal)? report,
  void Function(int unpackedBytes)? unpackedBytesProbe,
) {
  // The archive is opened and checked AGAIN, under the same rules as the
  // first look. That costs little (nothing is unpacked for it) and means
  // this step trusts the file only as far as it has just checked it.
  final zip = openBackupArchive(
    job.archivePath,
    job.limits,
    unpackedBytesProbe: unpackedBytesProbe,
  );
  try {
    // The covers this look finds must be exactly the ones the first look
    // listed: the same names in the same order. Anything else means the
    // file is not the one that was checked before the restore began.
    final found = listBackupCovers(zip).toWrite;
    if (found.length != listed.length) {
      throw const BoundedExtractionException(_archiveChanged);
    }
    for (var i = 0; i < listed.length; i++) {
      if (found[i] != listed[i]) {
        throw const BoundedExtractionException(_archiveChanged);
      }
    }
    var done = 0;
    for (final leaf in listed) {
      // `leaf` is one of the names this look found itself (the comparison
      // above), so it has passed `restorableCoverLeaf` and its entry is
      // there. The check only turns "cannot be missing" into a refusal
      // instead of a crash.
      final entry = zip.entry('$coverEntryPrefix$leaf');
      if (entry == null) {
        throw const BoundedExtractionException(_archiveChanged);
      }
      // `writeTo` refuses an existing file, holds the picture to the size
      // and the checksum the archive declares, and removes its own file
      // when the picture turns out damaged.
      zip.writeTo(entry, p.join(target.path, leaf));
      done++;
      report?.call(done, listed.length);
    }
  } finally {
    zip.close();
  }
}

/// Copies the phone's own cover files from [current] into [target]. A
/// folder among them is skipped; a phone without a covers folder has
/// nothing to carry over.
void _carryOver(
  Directory current,
  Directory target,
  void Function(int coversDone, int coversTotal)? report,
) {
  if (!current.existsSync()) return;
  final files = current.listSync().whereType<File>().toList();
  var done = 0;
  for (final entity in files) {
    entity.copySync(p.join(target.path, p.basename(entity.path)));
    done++;
    report?.call(done, files.length);
  }
}
