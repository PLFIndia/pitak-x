/// The sentences for a pick that did not work, where they are the SAME on
/// every page that lets the user choose a file (core/platform, decision
/// D24).
///
/// WHY THIS FILE EXISTS (beginner note): three pages choose a file through
/// the app's own picker (`document_picker.dart`): Restore, Import and
/// Merge. Four of the things that can go wrong mean the same on each of
/// them, so each has ONE sentence, kept here. A sentence that depends on
/// the page (how large a file may be, what kind of file it reads) lives
/// with that page: `restore_messages.dart`, `picked_file_messages.dart`.
///
/// Plain constants: no name, no path and no text of an error ever goes
/// into them (AGENTS.md §5 and §6.2).
library;

/// The document could not be read from the app it lives in.
const String documentUnreadableMessage =
    'That file could not be read. If it is kept online, check the '
    'connection and try again.';

/// The private copy could not be written on this device.
const String documentNotSavedMessage =
    'The file could not be copied to this phone. Free some storage and '
    'try again.';

/// There is no way to pick a document here (decision D19).
const String documentPickUnavailableMessage =
    'Choosing a file is not available on this device.';

/// Anything else went wrong while a file was chosen.
const String documentPickFailedMessage =
    'Something went wrong choosing the file. Please try again.';
