/// The sentences about saving a file where they are the SAME on every page
/// that saves one (core/platform; review finding P4-M6, decisions D170,
/// D176 and D184).
///
/// WHY THIS FILE EXISTS (beginner note): two pages save a file through the
/// app's own saver (`document_saver.dart`): Create backup and Export. Four
/// of the ways a save can end mean the same on both, so each has ONE
/// sentence, kept here. A sentence that depends on the page (what was
/// saved, what may be left at the place) lives with that page:
/// `create_backup_messages.dart`, `export_messages.dart`.
///
/// The wording was approved word for word, and a test holds it. Plain
/// constants: no name, no path and no text of an error ever goes into them
/// (AGENTS.md §5 and §6.2).
library;

/// The user closed the system's save window without choosing a place.
const String documentSaveNoPlaceMessage =
    'No place was chosen, so nothing was saved.';

/// There is no way to save a file here (decision D171).
const String documentSaveUnavailableMessage =
    'Saving to a file is not available on this device.';

/// The user chose a file that already holds something. The app never
/// replaces a file, so that one was left exactly as it is (decision D176).
const String documentSaveNotEmptyMessage =
    'That file already has something in it, so it was left as it is. '
    'Choose a new name in the save window and try again.';

/// The place the user chose cannot tell the app whether a file is stored
/// there. The app says "saved" only on the place's own word, so the file
/// was taken back (decisions D183 and D184).
const String documentSaveUnconfirmedMessage =
    'That place cannot confirm that a file is stored, so nothing was saved '
    'there. Choose a place on this phone or on a memory card, or use Share '
    'instead.';
