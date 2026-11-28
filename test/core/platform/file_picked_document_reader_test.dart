/// Decision D24: the copy of a picked document is read into memory under a
/// cap, and everything that can go wrong with the file is answered with
/// null, never with an exception.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/file_picked_document_reader.dart';

void main() {
  late Directory tmp;
  const reader = FilePickedDocumentReader();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('picked_document_reader_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A copy on disk that holds [bytes], described the way the picker
  /// describes one.
  PickedDocument copy(List<int> bytes, {String name = 'document'}) {
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return PickedDocument(
      path: file.path,
      displayName: 'library.json',
      sizeBytes: bytes.length,
    );
  }

  PickedDocument at(String path) =>
      PickedDocument(path: path, displayName: '', sizeBytes: 0);

  group('firstBytes', () {
    test('the first bytes of a longer copy, and no more', () async {
      final document = copy(List<int>.generate(200 * 1024, (i) => i % 251));
      expect(await reader.firstBytes(document, 4), [0, 1, 2, 3]);
    });

    test('all of a copy that is shorter than what was asked for', () async {
      expect(await reader.firstBytes(copy([7, 8]), 4), [7, 8]);
    });

    test('an empty copy is an empty list, not null', () async {
      final head = await reader.firstBytes(copy(const []), 4);
      expect(head, isNotNull);
      expect(head, isEmpty);
    });

    test('asking for no bytes answers an empty list without a look at the '
        'file', () async {
      final head = await reader.firstBytes(at('${tmp.path}/missing'), 0);
      expect(head, isEmpty);
    });
  });

  group('readAll', () {
    test('every byte of a copy of several blocks', () async {
      final bytes = List<int>.generate(200 * 1024 + 17, (i) => i % 251);
      expect(await reader.readAll(copy(bytes), maxBytes: bytes.length), bytes);
    });

    test('a copy of exactly the cap is read; one byte more is null', () async {
      final atCap = copy(List<int>.filled(1000, 1), name: 'at_cap');
      final over = copy(List<int>.filled(1001, 1), name: 'over');
      expect((await reader.readAll(atCap, maxBytes: 1000))!.length, 1000);
      expect(await reader.readAll(over, maxBytes: 1000), isNull);
    });

    test('the cap is counted on the file, not taken from the size the '
        'picker wrote down', () async {
      // The description says 3 bytes; the file holds 5,000.
      final file = File('${tmp.path}/document')
        ..writeAsBytesSync(List<int>.filled(5000, 1));
      final lying = PickedDocument(
        path: file.path,
        displayName: '',
        sizeBytes: 3,
      );
      expect(await reader.readAll(lying, maxBytes: 1024), isNull);
    });

    test('a cap that allows nothing answers null', () async {
      expect(await reader.readAll(copy([1]), maxBytes: 0), isNull);
    });
  });

  group('what is not a plain file is never opened', () {
    test('a copy that is gone: null from both, and nothing throws', () async {
      final gone = at('${tmp.path}/missing');
      expect(await reader.firstBytes(gone, 4), isNull);
      expect(await reader.readAll(gone, maxBytes: 10), isNull);
    });

    test('a folder: null from both', () async {
      final folder = Directory('${tmp.path}/folder')..createSync();
      expect(await reader.firstBytes(at(folder.path), 4), isNull);
      expect(await reader.readAll(at(folder.path), maxBytes: 10), isNull);
    });

    test('a link to a real file: null from both', () async {
      // A link could point anywhere, so it is refused although the file
      // behind it could be read.
      final target = File('${tmp.path}/target')..writeAsBytesSync([1, 2, 3]);
      final link = Link('${tmp.path}/link')..createSync(target.path);
      expect(await reader.firstBytes(at(link.path), 4), isNull);
      expect(await reader.readAll(at(link.path), maxBytes: 10), isNull);
    });
  });

  test('a plain file that cannot be opened: null from both, and nothing '
      'throws', () async {
    // The file is there and is a plain file, but reading it is not
    // allowed. That is the one case in which the read itself fails, so it
    // is what shows that an error of the disk ends as null.
    final document = copy([1, 2, 3, 4, 5]);
    Process.runSync('chmod', ['000', document.path]);
    addTearDown(() => Process.runSync('chmod', ['600', document.path]));
    var readable = true;
    try {
      File(document.path).openSync().closeSync();
    } on FileSystemException {
      readable = false;
    }
    if (readable) {
      // An administrator account may read every file, and Windows has no
      // `chmod`: the case cannot be made there.
      markTestSkipped('this account can read a file without permissions');
      return;
    }

    expect(await reader.firstBytes(document, 4), isNull);
    expect(await reader.readAll(document, maxBytes: 10), isNull);
  });

  test('the provider hands out the reader that reads from disk', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(pickedDocumentReaderProvider),
      isA<FilePickedDocumentReader>(),
    );
  });
}
