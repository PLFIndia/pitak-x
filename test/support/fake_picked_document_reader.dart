import 'dart:io';
import 'dart:typed_data';

import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';

/// A [PickedDocumentReader] for tests (decision D24): reads the copy the
/// fake picker wrote (`fake_document_picker.dart`), AT ONCE.
///
/// Why not the real reader (beginner note): a widget test runs on a made-up
/// clock, on which asynchronous file work never completes. This one reads
/// synchronously, so a page test can wait for it. The real reader has its
/// own tests (`file_picked_document_reader_test.dart`), and the controller
/// tests, which run on the real clock, use it.
///
/// What it does for a test besides reading:
///  - it writes down every call (`firstBytes 4`, `readAll 1024`), so a test
///    can show that a refused file was looked at and never loaded;
///  - [failing] makes every read answer null, as for a copy that cannot be
///    read.
final class FakePickedDocumentReader implements PickedDocumentReader {
  /// Every call so far, in order: the method and its number.
  final List<String> asked = [];

  /// When true, every read answers null.
  bool failing = false;

  @override
  Future<Uint8List?> firstBytes(PickedDocument document, int count) async {
    asked.add('firstBytes $count');
    final bytes = _bytesOf(document);
    if (bytes == null) return null;
    return Uint8List.sublistView(
      bytes,
      0,
      count < bytes.length ? count : bytes.length,
    );
  }

  @override
  Future<Uint8List?> readAll(
    PickedDocument document, {
    required int maxBytes,
  }) async {
    asked.add('readAll $maxBytes');
    final bytes = _bytesOf(document);
    if (bytes == null || bytes.length > maxBytes) return null;
    return bytes;
  }

  Uint8List? _bytesOf(PickedDocument document) {
    if (failing) return null;
    final file = File(document.path);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }
}
