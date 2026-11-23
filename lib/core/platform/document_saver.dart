/// "Save a copy of this file of mine where the user says" (core/platform;
/// review finding P4-M6, decisions D167, D168, D171 and D176).
///
/// WHY THIS EXISTS (beginner note): a backup or an export used to leave the
/// app through the share sheet only, and a phone whose sheet has no app for
/// such a file could not keep it at all. On Android the app therefore has
/// its own small piece of native code (`SavedDocumentChannel.kt`): it opens
/// the system's "save" window with the file's name filled in and copies the
/// file to the place the user confirms. Because the app does the copy
/// itself, it can ask the place whether the bytes are stored, and a page
/// says "saved" only then.
///
/// This file is the PORT: what the rest of the app may ask for, and the
/// answers it can get. It is pure Dart (no Flutter, no `dart:io`), so a page
/// or a controller may import it. The implementation that talks to Android
/// is `channel_document_saver.dart`. It is the mirror of
/// `document_picker.dart`, which brings a file IN.
///
/// WHO OWNS THE FILE: the caller. Saving reads the file and changes nothing
/// about it; whoever made it removes it afterwards, on every way out.
library;

/// What a saved file's name may be before its ending: plain letters, digits
/// and hyphens. The same text as `DocumentCopyOut.NAME_STEM` in Kotlin.
const String savableFileNameStem = '[A-Za-z0-9-]{1,120}';

/// The four endings a file that is saved may have. The same four as the
/// keys of `DocumentCopyOut.TYPES` in Kotlin, where each has its type.
const List<String> savableFileEndings = ['pitabak', 'json', 'csv', 'pdf'];

final RegExp _savableFileName = RegExp(
  '^$savableFileNameStem\\.(${savableFileEndings.join('|')})\$',
);

/// Whether [name] is a name a file may be saved under.
///
/// WHY SO NARROW (beginner note): the Android side takes the proposed name
/// and the file's type from this name, and refuses every other file. So
/// the name can hold nothing a path could use (no slash, no dot but the one
/// before the ending, no space), and only the four kinds of file the app
/// makes for keeping. Whoever writes such a file checks its name with this
/// function first, so that a wrong name fails where it is made.
bool isSavableFileName(String name) => _savableFileName.hasMatch(name);

/// A file that was saved where the user said.
final class SavedDocument {
  /// Creates the description of one saved file.
  const SavedDocument({required this.displayName, required this.sizeBytes});

  /// What the place calls the file now. It can differ from the name the app
  /// proposed (the user may type another, and a name that exists gets a
  /// number). FOR SHOWING ONLY: it is foreign text and must never be used
  /// as a file name or a path. It can be empty.
  final String displayName;

  /// Size of the saved file in bytes, counted while it was copied.
  final int sizeBytes;

  /// Shows the size only: the name stays out of logs (§6.2).
  @override
  String toString() => 'SavedDocument($sizeBytes bytes)';
}

/// How a save ended. A closed set (sealed), so a `switch` over it has to
/// name every case and none can be forgotten.
sealed class DocumentSaveResult {
  const DocumentSaveResult();
}

/// Every byte of the file was written to the place the user chose, and the
/// place said that the bytes are stored.
final class DocumentSaved extends DocumentSaveResult {
  /// Wraps the description of the saved file.
  const DocumentSaved(this.document);

  /// What was saved: the place's name for it, and its size.
  final SavedDocument document;
}

/// The user closed the save window without choosing a place. Not an error;
/// nothing was written anywhere.
final class DocumentSaveCancelled extends DocumentSaveResult {
  /// The user chose no place.
  const DocumentSaveCancelled();
}

/// The place could not take the file (no free storage, a drive that went
/// away), or said at the end that the bytes are not stored (decision D182).
/// The unfinished file was removed again: nothing was left behind.
final class DocumentSaveNotSaved extends DocumentSaveResult {
  /// The file could not be saved there.
  const DocumentSaveNotSaved();
}

/// The app's own file could not be read any more (the system may empty the
/// temporary folder while the save window is open). Nothing was left
/// behind at the place.
final class DocumentSaveSourceGone extends DocumentSaveResult {
  /// The file to save is gone.
  const DocumentSaveSourceGone();
}

/// The save failed AND the unfinished file could not be removed again, or
/// the answer about it could not be trusted. Something that is not a whole
/// file may lie at the place, and the user has to be told.
final class DocumentSaveLeftBehind extends DocumentSaveResult {
  /// An unfinished file may be left at the place.
  const DocumentSaveLeftBehind();
}

/// The user chose a file that already has something in it (the system's
/// window offers to replace one). The app never replaces a file: that file
/// was not opened, not changed and not removed (decision D176).
final class DocumentSaveNotEmpty extends DocumentSaveResult {
  /// The chosen file already holds something and was left as it is.
  const DocumentSaveNotEmpty();
}

/// Every byte was written, but the place is of a kind that cannot be asked
/// whether the bytes are stored, so nothing vouches for the file. It was
/// removed again: nothing was left behind, and nothing counts as saved
/// (decisions D182 and D183).
final class DocumentSaveUnconfirmed extends DocumentSaveResult {
  /// The place cannot confirm that a file is stored.
  const DocumentSaveUnconfirmed();
}

/// There is no way to save a file here: the app's native side is missing
/// (any platform but Android, D171) or the device has no save window.
final class DocumentSaveUnavailable extends DocumentSaveResult {
  /// Saving is not available.
  const DocumentSaveUnavailable();
}

/// Anything else went wrong: a mistake in code on either side. As far as
/// this side knows, nothing was written.
final class DocumentSaveFailed extends DocumentSaveResult {
  /// The save failed.
  const DocumentSaveFailed();
}

/// Saves a copy of one finished file of the app where the user says.
// One method on purpose: the port has one job. (A class and not a plain
// function, so that a test can put a stand-in in its place through the
// provider, as for every other port of this folder.)
// ignore: one_member_abstracts
abstract interface class DocumentSaver {
  /// Opens the system's save window with the name of the file at [path]
  /// filled in, and copies the file to the place the user confirms.
  ///
  /// [path] must name a finished file in one of the app's own working
  /// folders, called as [isSavableFileName] allows. The file is only read.
  /// Never throws; see [DocumentSaveResult] for the answers.
  Future<DocumentSaveResult> saveCopy({required String path});
}
