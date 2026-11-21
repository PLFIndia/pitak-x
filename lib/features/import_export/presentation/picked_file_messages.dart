/// The sentences the Import and Merge pages show when a chosen file was
/// not taken (presentation layer, AGENTS.md §5: typed answers in, safe text
/// out, never raw exception text).
///
/// WHY THIS FILE EXISTS (beginner note): since decision D24 neither page
/// reads the chosen file itself. Its controller does, and answers with a
/// [PickedFileProblem] when no file was taken. Each problem gets a plain
/// sentence here. Pure functions, kept out of the pages so they can be
/// tested without pumping a widget, as `restore_messages.dart` does for
/// the Restore page.
library;

import 'package:pitaka/core/platform/document_pick_messages.dart';
import 'package:pitaka/core/text/display_number.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart'
    show kImportZipRefusedMessage;
import 'package:pitaka/features/import_export/application/picked_text_file.dart';

/// Which page asks: the two word their "too large" sentence differently.
enum PickedFileUse {
  /// The Import page.
  import,

  /// The Merge page.
  merge,
}

/// The sentence for a chosen file that was not taken.
///
/// [maxBytes] is the largest file the page reads; the "too large" sentence
/// names it.
///
/// The switch has no default ON PURPOSE: the problems are a closed set, so
/// a new one does not compile until it has a sentence here.
String pickedFileProblemMessage(
  PickedFileProblem problem, {
  required PickedFileUse use,
  required int maxBytes,
}) => switch (problem) {
  PickedFileProblem.tooLarge => switch (use) {
    // A backup above the cap is turned away by the picker before a byte of
    // it is copied, so nobody can look at it to see that it is a ZIP. The
    // page knows only "too large", and a backup picked by mistake is the
    // likeliest reason, so the sentence says where a backup goes.
    PickedFileUse.import =>
      'This file is too large to import. Import reads files of up to '
          '${_size(maxBytes)}. To load a backup (.pitabak), use '
          '\u201cRestore backup\u201d.',
    PickedFileUse.merge =>
      'This file is too large to merge. A library file can be at most '
          '${_size(maxBytes)}.',
  },
  PickedFileProblem.unreadable => documentUnreadableMessage,
  PickedFileProblem.notSaved => documentNotSavedMessage,
  PickedFileProblem.unavailable => documentPickUnavailableMessage,
  PickedFileProblem.failed => documentPickFailedMessage,
  // Only Import answers this (D29); the sentence is Import's.
  PickedFileProblem.zipFile => kImportZipRefusedMessage,
};

/// One size as the other pages write sizes ("64.0 MB").
String _size(int bytes) => formatSizePair(bytes, bytes).first;
