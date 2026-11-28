/// "Let the user choose one document and give me a private copy of it"
/// (core/platform, backup rework BR5b, decisions D8 and D19).
///
/// WHY THIS EXISTS (beginner note): the `file_selector` plugin loads the
/// whole chosen file into memory before any of our size checks can run
/// (safety check SC1). A backup of hundreds of megabytes ends the app that
/// way. On Android the app therefore has its own small piece of native code
/// (`PickedDocumentChannel.kt`): it opens the same system picker, but COPIES
/// the document into the app's private temporary folder while counting the
/// bytes, and hands back the path of that copy.
///
/// This file is the PORT: what the rest of the app may ask for, and the
/// answers it can get. It is pure Dart (no Flutter, no `dart:io`), so a page
/// or a controller may import it. The implementation that talks to Android
/// is `channel_document_picker.dart`.
///
/// WHO OWNS THE COPY: whoever called [DocumentPicker.pickCopy] owns the copy
/// until it calls [DocumentPicker.discard]. A copy is a plain duplicate of
/// the user's file, so it must not be left behind.
library;

/// A private copy of a document the user chose.
final class PickedDocument {
  /// Creates the description of one picked copy.
  const PickedDocument({
    required this.path,
    required this.displayName,
    required this.sizeBytes,
  });

  /// Where the copy lies, inside the app's own temporary folder. The file
  /// has a fixed name of ours; it does not carry the document's name.
  final String path;

  /// What the app the document came from calls it. FOR SHOWING ONLY: it is
  /// foreign text and must never be used as a file name or a path. It can
  /// be empty.
  final String displayName;

  /// Size of the copy in bytes, counted while it was copied.
  final int sizeBytes;

  /// Shows the size only: the name and the path stay out of logs (§6.2).
  @override
  String toString() => 'PickedDocument($sizeBytes bytes)';
}

/// How a pick ended. A closed set (sealed), so a `switch` over it has to
/// name every case and none can be forgotten.
sealed class DocumentPickResult {
  const DocumentPickResult();
}

/// The user chose a document and its copy is ready.
final class DocumentPicked extends DocumentPickResult {
  /// Wraps the picked copy.
  const DocumentPicked(this.document);

  /// The copy. The caller owns it until [DocumentPicker.discard].
  final PickedDocument document;
}

/// The user closed the picker without choosing anything. Not an error.
final class DocumentPickCancelled extends DocumentPickResult {
  /// The user chose nothing.
  const DocumentPickCancelled();
}

/// The document holds more bytes than the cap. Nothing was kept.
final class DocumentPickTooLarge extends DocumentPickResult {
  /// The document is larger than the cap.
  const DocumentPickTooLarge();
}

/// The document could not be read from the app it lives in. Nothing was
/// kept.
final class DocumentPickUnreadable extends DocumentPickResult {
  /// The document could not be read.
  const DocumentPickUnreadable();
}

/// The copy could not be written on this device (for example: no free
/// storage). Nothing was kept.
final class DocumentPickNotSaved extends DocumentPickResult {
  /// The copy could not be saved.
  const DocumentPickNotSaved();
}

/// There is no way to pick a document here: the app's native side is
/// missing (any platform but Android, D19) or the device has no picker.
final class DocumentPickUnavailable extends DocumentPickResult {
  /// Picking is not available.
  const DocumentPickUnavailable();
}

/// Anything else went wrong, including an answer from the native side that
/// did not pass the checks. Nothing was kept.
final class DocumentPickFailed extends DocumentPickResult {
  /// The pick failed.
  const DocumentPickFailed();
}

/// Lets the user choose one document and keeps a private, size-capped copy
/// of it.
abstract interface class DocumentPicker {
  /// Opens the system's document picker and copies the chosen document
  /// into the app's temporary folder.
  ///
  /// The copy never holds more than [maxBytes] bytes: the bytes are counted
  /// while they arrive, whatever size the document announces. Never throws;
  /// see [DocumentPickResult] for the answers.
  Future<DocumentPickResult> pickCopy({required int maxBytes});

  /// Removes a copy that [pickCopy] handed out.
  ///
  /// Never throws and may be called twice. A copy that could not be removed
  /// now is removed by the next [sweep].
  Future<void> discard(PickedDocument document);

  /// Removes every picked copy that nobody of this app session owns: what a
  /// killed app left behind. Never throws.
  Future<void> sweep();
}
