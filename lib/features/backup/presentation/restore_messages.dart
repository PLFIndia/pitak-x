/// The sentences the restore page shows while a backup file is chosen and
/// copied, when choosing it did not work, and when a restore had to leave
/// cover pictures out (presentation layer, AGENTS.md §5: typed answers in,
/// safe text out, never raw exception text).
///
/// WHY THIS FILE EXISTS (beginner note): since the streamed restore (backup
/// rework BR6) the page no longer reads the chosen file itself. The app's
/// own picker copies it into a private folder and answers in one of seven
/// ways (`DocumentPickResult`). Each answer a user can do something about
/// gets its own plain sentence here.
///
/// Pure functions, kept out of the page so they can be tested without
/// pumping a widget, as `create_backup_messages.dart` does for the backup
/// page.
library;

import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/text/display_number.dart';

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
  DocumentPickTooLarge() =>
    'This file is too large to be a Pitak backup. A backup file can be at '
        'most ${_size(maxArchiveBytes)}.',
  DocumentPickUnreadable() =>
    'That file could not be read. If it is kept online, check the '
        'connection and try again.',
  DocumentPickNotSaved() =>
    'The file could not be copied to this phone. Free some storage and '
        'try again.',
  DocumentPickUnavailable() =>
    'Choosing a file is not available on this device.',
  DocumentPickFailed() =>
    'Something went wrong choosing the file. Please try again.',
};

/// One size as the other pages write sizes ("504.0 MB").
String _size(int bytes) => formatSizePair(bytes, bytes).first;

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
