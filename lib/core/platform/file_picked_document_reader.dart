/// The [PickedDocumentReader] that reads from disk (core/platform, decision
/// D24).
///
/// A picked document's copy lies in the app's private temporary folder
/// (`<temp>/picked_documents/pick-<random>/document`), where the app's own
/// picker put it under a size cap. This class reads it into memory, again
/// under a cap: the rule "never more than the cap in memory" then holds
/// here too, whatever happened to the file in between.
///
/// FAIL CLOSED (beginner note): everything that can go wrong with a file
/// (it is gone, it is a folder or a link, the disk reports an error) ends
/// as `null`, never as an exception and never as half a file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pitaka/core/platform/bounded_file_read.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';

/// See the library doc.
final class FilePickedDocumentReader implements PickedDocumentReader {
  /// Creates the reader. It holds nothing.
  const FilePickedDocumentReader();

  @override
  Future<Uint8List?> firstBytes(PickedDocument document, int count) async {
    if (count <= 0) return Uint8List(0);
    if (!_isPlainFile(document.path)) return null;
    try {
      // `openRead(0, count)` stops after `count` bytes, or at the end of a
      // shorter file. `collectBounded` counts once more, so that not even a
      // mistake in that range could load more than was asked for.
      return await collectBounded(
        File(document.path).openRead(0, count),
        maxBytes: count,
      );
    } on FileSystemException {
      // The copy could not be opened or read: answered as "cannot be read".
      return null;
    }
  }

  @override
  Future<Uint8List?> readAll(
    PickedDocument document, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) return null;
    if (!_isPlainFile(document.path)) return null;
    try {
      return await readFileBounded(document.path, maxBytes: maxBytes);
    } on FileSystemException {
      // The copy could not be opened or read: answered as "cannot be read".
      return null;
    }
  }

  /// Whether [path] is a real file: not a folder, not a link, not missing.
  /// A link is refused because it could point anywhere. (`typeSync` does
  /// not throw: what it cannot look at is "not found".)
  static bool _isPlainFile(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;
}
