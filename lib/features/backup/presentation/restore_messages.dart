/// The sentences the restore page shows while a backup file is chosen and
/// copied, when choosing it did not work, when the file holds more than a
/// backup can, and when a restore had to leave cover pictures out
/// (presentation layer, AGENTS.md §5: typed answers in, safe text out,
/// never raw exception text).
///
/// WHY THIS FILE EXISTS (beginner note): since the streamed restore (backup
/// rework BR6) the page no longer reads the chosen file itself. The app's
/// own picker copies it into a private folder and answers in one of seven
/// ways (`DocumentPickResult`). Each answer a user can do something about
/// gets its own plain sentence. The four that read the same on every page
/// that picks a file come from `document_pick_messages.dart`; the one that
/// names a backup and its size is here.
///
/// Pure functions, kept out of the page so they can be tested without
/// pumping a widget, as `create_backup_messages.dart` does for the backup
/// page.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_pick_messages.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/text/display_number.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';

/// The line under the "Choose" button while the system's picker is open
/// and the chosen file is being copied into the app (decision D26).
///
/// A file kept online is downloaded by the app it lives in while it is
/// copied, which can take minutes. The line says so, because nothing else
/// on the page moves meanwhile.
const String restoreCopyingMessage =
    'Copying the file… A large backup, or one kept online, can take a while.';

/// The sentence for how choosing a backup file ended, or null when there
/// is nothing to say: the file was picked, or the user closed the picker
/// without choosing.
///
/// [maxArchiveBytes] is the largest backup file the app takes; the "too
/// large" sentence names it.
///
/// The switch has no default ON PURPOSE: the answers are a closed set, so
/// a new answer does not compile until it has a sentence here.
String? restorePickMessage(
  DocumentPickResult result, {
  required int maxArchiveBytes,
}) => switch (result) {
  DocumentPicked() || DocumentPickCancelled() => null,
  DocumentPickTooLarge() => _fileTooLarge(maxArchiveBytes),
  DocumentPickUnreadable() => documentUnreadableMessage,
  DocumentPickNotSaved() => documentNotSavedMessage,
  DocumentPickUnavailable() => documentPickUnavailableMessage,
  DocumentPickFailed() => documentPickFailedMessage,
};

/// One size as the other pages write sizes ("1.0 GB").
String _size(int bytes) => formatSizePair(bytes, bytes).first;

/// The sentence for a file that is larger than a backup file can be. Said
/// by the picker while it copies the file, and by the reader, which looks
/// at the size once more when it opens the copy.
String _fileTooLarge(int maxArchiveBytes) =>
    'This file is too large to be a Pitak backup. A backup file can be at '
    'most ${_size(maxArchiveBytes)}.';

/// The first half of the two sentences below, and the whole sentence when a
/// failure does not say which limit it was or gives no number. It is still
/// true then.
const String restoreBeyondLimitsFallbackMessage =
    'This file holds more than a Pitak backup can.';

/// The sentence for a file in which one part a restore cannot do without
/// (the list of items, the wishlist, the borrowers vault, the table of
/// contents) is larger than a backup allows. No number: the caps differ
/// from part to part.
const String restorePartTooLargeMessage =
    'One part of this file is larger than a Pitak backup allows.';

/// The sentence for a file that holds more than a backup can (backup
/// rework BR8, decision D41; review finding P4-m19).
///
/// WHY (beginner note): until BR8 the page called such a file "not a valid
/// Pitak backup". But it can be a real backup: one made by an older
/// version, which had no limits when it wrote, or by a later version with
/// higher limits. "Too much" and "damaged" are different news, so they get
/// different sentences.
///
/// "This file", not "this backup": the app does not know that it is one.
/// The number in a sentence is the app's own limit ([failure]'s `limit`).
/// Nothing the file says about itself is shown, neither a name nor a count.
///
/// `failure.detail` carries the NAME of a [BackupOverflow] code, as it does
/// on the create-backup page (`backupTooLargeMessage`): one vocabulary for
/// "which limit", and each page has its own sentences for it.
String restoreBeyondLimitsMessage(BackupTooLargeFailure failure) {
  final code = BackupOverflow.values.asNameMap()[failure.detail];
  final limit = failure.limit;
  if (code == null) return restoreBeyondLimitsFallbackMessage;
  // The switch has no default ON PURPOSE: a new code does not compile until
  // someone decides here what the restore page says for it.
  return switch (code) {
    BackupOverflow.tooManyCovers =>
      limit == null
          ? restoreBeyondLimitsFallbackMessage
          : '$restoreBeyondLimitsFallbackMessage A backup can hold '
                '${formatCount(limit)} cover pictures.',
    BackupOverflow.contentTooLarge =>
      limit == null
          ? restoreBeyondLimitsFallbackMessage
          : '$restoreBeyondLimitsFallbackMessage A backup can hold '
                '${_size(limit)}.',
    BackupOverflow.archiveTooLarge =>
      limit == null ? restoreBeyondLimitsFallbackMessage : _fileTooLarge(limit),
    BackupOverflow.entryTooLarge => restorePartTooLargeMessage,
    // The codes below are the WRITER's alone: it checks the parts of the
    // catalogue and their rows before it packs. The reader of a restore
    // never gives them. Named one by one so that the switch stays complete.
    BackupOverflow.catalogueTooLarge ||
    BackupOverflow.wishlistTooLarge ||
    BackupOverflow.vaultTooLarge ||
    BackupOverflow.itemKindsTooLarge ||
    BackupOverflow.itemKindsTooManyRows ||
    BackupOverflow.periodicalsTooLarge ||
    BackupOverflow.periodicalsTooManyRows => restoreBeyondLimitsFallbackMessage,
  };
}

/// The sentence above the list of items whose cover picture was too large
/// and was not restored (decisions D18 and D23). [count] is the number of
/// such items and must be at least 1.
///
/// The twin of `coversLeftOutMessage` on the create-backup page: there the
/// picture is not inside the backup, here it was inside and is not brought
/// back. Either way the item itself is there.
String restoreCoversLeftOutMessage(int count) => count == 1
    ? 'Note: the cover picture of 1 item in this backup is too large and '
          'was not restored. The item itself was restored:'
    : 'Note: the cover pictures of ${formatCount(count)} items in this '
          'backup are too large and were not restored. The items themselves '
          'were restored:';
