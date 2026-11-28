/// "Let the user choose a text file and give me its bytes" for Import and
/// Merge (application layer, decision D24).
///
/// THE WAY OF A FILE (beginner note): the app's own picker
/// (`DocumentPicker`) copies the chosen document into the app's private
/// temporary folder and stops at a size cap, so a file that is too large
/// never reaches memory. [pickAndReadText] then reads that copy and REMOVES
/// it. The copy is a plain duplicate of the user's file, so it must not be
/// left behind.
///
/// WHO OWNS THE COPY: this one function, from the moment the picker answers
/// "picked" until `discard`. There is one `try` with a `finally` around
/// everything that is done with the copy. No page and no field of a
/// controller ever holds it. (The Restore page is different: it keeps its
/// copy while the user types a passphrase, see `restore_controller.dart`.)
/// When the app is killed in between, the sweep at the next start removes
/// the copy.
library;

import 'dart:typed_data';

import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart'
    show hasZipLocalFileHeader;

/// Why a chosen file was not taken. The page turns each into a sentence
/// (`picked_file_messages.dart`).
enum PickedFileProblem {
  /// The file holds more bytes than the cap.
  tooLarge,

  /// The file, or the app's copy of it, could not be read.
  unreadable,

  /// The copy could not be written on this device.
  notSaved,

  /// There is no way to pick a file here (decision D19).
  unavailable,

  /// Anything else went wrong while the file was chosen.
  failed,

  /// The file is a ZIP, which Import does not read (decision D29). Merge
  /// never answers this: it hands every file to its parser.
  zipFile,
}

/// How [pickAndReadText] ended. A closed set (sealed), so a `switch` over
/// it has to name every case.
sealed class PickedText {
  const PickedText();
}

/// A file was chosen and read. Its copy is already removed.
final class PickedTextRead extends PickedText {
  /// Wraps the file's bytes.
  const PickedTextRead(this.bytes);

  /// Every byte of the file; never more than the cap.
  final Uint8List bytes;
}

/// The user closed the picker without choosing anything. Not an error.
final class PickedTextNothing extends PickedText {
  /// Nothing was chosen.
  const PickedTextNothing();
}

/// A file was chosen but not taken. Nothing of it is kept.
final class PickedTextProblem extends PickedText {
  /// Wraps the reason.
  const PickedTextProblem(this.problem);

  /// Why the file was not taken.
  final PickedFileProblem problem;
}

/// Opens the system's picker, reads the chosen file and removes the app's
/// copy of it.
///
/// Neither the copy nor the bytes ever hold more than [maxBytes]: the
/// picker counts while it copies, and the reader counts again while it
/// reads.
///
/// With [refuseZip] the first four bytes are looked at BEFORE the file is
/// read: a ZIP (a backup picked by mistake, most likely) is answered with
/// [PickedFileProblem.zipFile] and is never loaded. This is where the rule
/// "Import reads no ZIP" (D29) is applied to a picked file.
///
/// Never throws for anything the picker or the reader answers; the copy is
/// removed on every way out.
Future<PickedText> pickAndReadText({
  required DocumentPicker picker,
  required PickedDocumentReader reader,
  required int maxBytes,
  required bool refuseZip,
}) async {
  final answer = await picker.pickCopy(maxBytes: maxBytes);
  // Each of the seven answers is named; a new one would not compile.
  switch (answer) {
    case DocumentPickCancelled():
      return const PickedTextNothing();
    case DocumentPickTooLarge():
      return const PickedTextProblem(PickedFileProblem.tooLarge);
    case DocumentPickUnreadable():
      return const PickedTextProblem(PickedFileProblem.unreadable);
    case DocumentPickNotSaved():
      return const PickedTextProblem(PickedFileProblem.notSaved);
    case DocumentPickUnavailable():
      return const PickedTextProblem(PickedFileProblem.unavailable);
    case DocumentPickFailed():
      return const PickedTextProblem(PickedFileProblem.failed);
    case DocumentPicked(:final document):
      // From here on there is a copy on disk, and this function owns it.
      try {
        if (refuseZip) {
          final head = await reader.firstBytes(document, 4);
          if (head == null) {
            return const PickedTextProblem(PickedFileProblem.unreadable);
          }
          if (hasZipLocalFileHeader(head)) {
            return const PickedTextProblem(PickedFileProblem.zipFile);
          }
        }
        final bytes = await reader.readAll(document, maxBytes: maxBytes);
        if (bytes == null) {
          return const PickedTextProblem(PickedFileProblem.unreadable);
        }
        return PickedTextRead(bytes);
      } finally {
        // On every way out, also when a read threw. `discard` never throws.
        await picker.discard(document);
      }
  }
}
