/// Turns what a worker of a restore answered when it STOPPED into the
/// failure the Restore page gets (backup infrastructure; backup rework BR8,
/// decision D41, review finding P4-m19).
///
/// WHY THIS FILE EXISTS (beginner note): the reader refuses a file for many
/// reasons. Until BR8 every one of them became "this file is damaged"
/// (`BackupCorruptFailure`), and the page said "This file doesn’t look like
/// a valid Pitak backup." That is the wrong thing to say about a real
/// backup that only holds more than a backup can: one made by an older
/// version that had no limits, or by a later one with higher limits.
///
/// The reader says which KIND of refusal it was (`ZipRefusal`), in the
/// words of ZIP files. [restoreRefusalFailure] says what that means for a
/// backup: a failure with the name of the limit and the app's own number
/// for it. The number comes from `BackupLimits`, never from the file, so
/// nothing a file claims about itself reaches the screen.
///
/// The codes are the ones the backup WRITER refuses with (`BackupOverflow`),
/// on purpose: "too many covers" means the same thing whether the app
/// declines to write such a backup or to read one. One vocabulary, two
/// pages; each page has its own sentences.
///
/// The failures are made on the CALLING isolate, here: no `Failure` object
/// crosses the border between isolates, only a refusal's text and kind, or
/// a code for trouble with the disk.
///
/// In a file of its own because `restore_backup.dart` is close to the
/// 500-line ceiling, and so that the table can be tested without a restore.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart'
    show RestoreDiskTrouble;
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';

/// What the user reads when the backup file itself can no longer be opened
/// or read (the private copy is gone: the system may clear the app's
/// temporary folder when storage is short). A sentence of its own, because
/// "could not write the restored data" would be untrue, and because there
/// is something the user can do.
const String restoreArchiveUnreadableMessage =
    'The backup file could not be read. Please choose it again.';

/// The typed failure for what a worker of a restore answered, or null when
/// it did not stop.
///
/// [refusal] and [kind] are the reader's refusal (its text and what kind it
/// was); [trouble] is trouble with the disk. A worker sets at most one of
/// the two. [limits] are the limits the restore runs under.
///
/// A refusal without a kind cannot happen: the workers set both. Should
/// one ever be missing, the file is read as damaged, the safe reading.
Failure? restoreStopFailure({
  required String? refusal,
  required ZipRefusal? kind,
  required RestoreDiskTrouble? trouble,
  required BackupLimits limits,
}) {
  if (refusal != null) {
    return restoreRefusalFailure(
      text: refusal,
      kind: kind ?? ZipRefusal.other,
      limits: limits,
    );
  }
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

/// The failure for a backup file the reader refused.
///
/// [text] is the reader's message, kept as the diagnostic of a damaged
/// file (it is never shown to a user). [kind] is what the reader said the
/// refusal was. [limits] are the limits the reader was given.
///
///  - [ZipRefusal.tooManyEntries]: more entries than a backup has. The
///    failure names the promise the app makes about a backup, "so many
///    COVER PICTURES" ([BackupLimits.maxCovers]), not the entry count the
///    reader works with (the covers plus the up to ten other files);
///  - [ZipRefusal.contentTooLarge]: more content than a backup holds
///    ([BackupLimits.maxContentBytes]);
///  - [ZipRefusal.fileTooLarge]: a larger file than a backup can be
///    ([BackupLimits.maxArchiveBytes]). The picker stops such a file while
///    it is copied; this is the reader's own second look;
///  - [ZipRefusal.entryTooLarge]: one part a restore cannot do without is
///    above its cap. No number: the caps differ from part to part, and the
///    part's name is the file's to claim;
///  - [ZipRefusal.other]: damaged, not a ZIP, or hostile. As before BR8.
///
/// The switch has no default ON PURPOSE: a new kind does not compile until
/// someone decides here what it means for a backup.
Failure restoreRefusalFailure({
  required String text,
  required ZipRefusal kind,
  required BackupLimits limits,
}) => switch (kind) {
  ZipRefusal.tooManyEntries => BackupTooLargeFailure(
    BackupOverflow.tooManyCovers.name,
    null,
    limits.maxCovers,
  ),
  ZipRefusal.contentTooLarge => BackupTooLargeFailure(
    BackupOverflow.contentTooLarge.name,
    null,
    limits.maxContentBytes,
  ),
  ZipRefusal.fileTooLarge => BackupTooLargeFailure(
    BackupOverflow.archiveTooLarge.name,
    null,
    limits.maxArchiveBytes,
  ),
  ZipRefusal.entryTooLarge => BackupTooLargeFailure(
    BackupOverflow.entryTooLarge.name,
  ),
  ZipRefusal.other => BackupCorruptFailure(text),
};
