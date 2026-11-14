/// "Give me the bytes of a document the user picked" (core/platform,
/// decision D24).
///
/// WHY THIS EXISTS (beginner note): the app's own picker
/// (`document_picker.dart`) does not hand out a file's bytes. It hands out
/// a private COPY on disk, a [PickedDocument]. A restore works on that file
/// as it is. Import and Merge need the text in memory, so somebody has to
/// read the copy. Controllers live in the application layer, which may not
/// touch files itself (AGENTS.md §3.1), so they ask through this PORT.
///
/// This file is pure Dart (no Flutter, no `dart:io`). The implementation
/// that reads from disk is `file_picked_document_reader.dart`; tests use a
/// fake.
///
/// The reader only READS. Removing the copy stays the job of whoever picked
/// it (`DocumentPicker.discard`).
library;

import 'dart:typed_data';

import 'package:pitaka/core/platform/document_picker.dart';

/// Reads the private copy of a picked document.
///
/// Neither method throws: a copy that cannot be read is answered with null,
/// and the caller turns that into a sentence.
abstract interface class PickedDocumentReader {
  /// The first [count] bytes of [document]'s copy, or all of it when it is
  /// shorter. Null when the copy cannot be read.
  ///
  /// For a look at what kind of file it is before anything more of it is
  /// loaded.
  Future<Uint8List?> firstBytes(PickedDocument document, int count);

  /// Every byte of [document]'s copy. Null when the copy cannot be read or
  /// holds more than [maxBytes] bytes.
  ///
  /// The cap is inclusive, and it is counted on the bytes that arrive, not
  /// taken from the size the picker wrote down.
  Future<Uint8List?> readAll(PickedDocument document, {required int maxBytes});
}
