/// Decision D24: Import and Merge get a chosen file through the app's own
/// picker. `pickAndReadText` is the one place that holds the private copy:
/// these tests guard that every answer of the picker is passed on, that the
/// cap reaches both the picker and the read, that a ZIP is refused on four
/// bytes without being loaded, and that the copy is removed on every way
/// out.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/file_picked_document_reader.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';
import 'package:pitaka/features/import_export/application/picked_text_file.dart';

import '../../support/fake_document_picker.dart';
import '../../support/fake_picked_document_reader.dart';

/// A reader that breaks its promise never to throw.
class _ThrowingReader implements PickedDocumentReader {
  @override
  Future<Uint8List?> firstBytes(PickedDocument document, int count) =>
      throw StateError('private path');

  @override
  Future<Uint8List?> readAll(
    PickedDocument document, {
    required int maxBytes,
  }) => throw StateError('private path');
}

void main() {
  late Directory tmp;
  late FakeDocumentPicker picker;
  late FakePickedDocumentReader reader;

  final json = utf8.encode('{"schemaVersion":3,"books":[]}');
  // The four bytes every ZIP file starts with, and something behind them.
  const zip = [0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0, 9, 9, 9];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('picked_text_file_test');
    picker = FakeDocumentPicker(Directory('${tmp.path}/picked_documents'));
    reader = FakePickedDocumentReader();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<PickedText> pick({bool refuseZip = true, int maxBytes = 1000}) =>
      pickAndReadText(
        picker: picker,
        reader: reader,
        maxBytes: maxBytes,
        refuseZip: refuseZip,
      );

  group('a pick that hands out no file', () {
    test('closing the picker is "nothing", not a problem', () async {
      picker.willAnswer(const DocumentPickCancelled());
      expect(await pick(), isA<PickedTextNothing>());
      expect(reader.asked, isEmpty);
      expect(picker.discarded, isEmpty);
    });

    // Each answer of the picker has exactly one problem.
    const answers = <(DocumentPickResult, PickedFileProblem)>[
      (DocumentPickTooLarge(), PickedFileProblem.tooLarge),
      (DocumentPickUnreadable(), PickedFileProblem.unreadable),
      (DocumentPickNotSaved(), PickedFileProblem.notSaved),
      (DocumentPickUnavailable(), PickedFileProblem.unavailable),
      (DocumentPickFailed(), PickedFileProblem.failed),
    ];
    for (final (answer, problem) in answers) {
      test('${answer.runtimeType} is passed on as ${problem.name}', () async {
        picker.willAnswer(answer);
        final result = await pick();
        expect(result, isA<PickedTextProblem>());
        expect((result as PickedTextProblem).problem, problem);
        expect(reader.asked, isEmpty, reason: 'there is nothing to read');
        expect(picker.discarded, isEmpty);
      });
    }
  });

  group('a picked file', () {
    test('is read, and its copy is removed', () async {
      picker.willPick(json);
      final result = await pick();

      expect(result, isA<PickedTextRead>());
      expect((result as PickedTextRead).bytes, json);
      expect(picker.discarded, hasLength(1));
      expect(picker.copiesOnDisk(), isEmpty);
    });

    test('the same cap goes to the picker and to the read', () async {
      picker.willPick(json);
      await pick(maxBytes: 4321, refuseZip: false);

      expect(picker.caps, [4321]);
      expect(reader.asked, ['readAll 4321']);
    });

    test('the kind of file is looked at on four bytes, then it is '
        'read', () async {
      picker.willPick(json);
      await pick();
      expect(reader.asked, ['firstBytes 4', 'readAll 1000']);
    });

    test('a file shorter than four bytes is read like any other', () async {
      picker.willPick(utf8.encode('{}'));
      final result = await pick();
      expect((result as PickedTextRead).bytes, utf8.encode('{}'));
    });

    test('the real reader reads the copy the picker made', () async {
      picker.willPick(json);
      final result = await pickAndReadText(
        picker: picker,
        reader: const FilePickedDocumentReader(),
        maxBytes: 1000,
        refuseZip: true,
      );
      expect((result as PickedTextRead).bytes, json);
      expect(picker.copiesOnDisk(), isEmpty);
    });
  });

  group('a ZIP (D29)', () {
    test('is refused after a look at four bytes; it is never loaded, and '
        'its copy is removed', () async {
      picker.willPick(zip);
      final result = await pick();

      expect(result, isA<PickedTextProblem>());
      expect((result as PickedTextProblem).problem, PickedFileProblem.zipFile);
      expect(reader.asked, ['firstBytes 4']);
      expect(picker.discarded, hasLength(1));
      expect(picker.copiesOnDisk(), isEmpty);
    });

    test('is read like any file when the caller does not ask for the '
        'refusal (Merge)', () async {
      picker.willPick(zip);
      final result = await pick(refuseZip: false);

      expect((result as PickedTextRead).bytes, zip);
      expect(reader.asked, ['readAll 1000']);
      expect(picker.copiesOnDisk(), isEmpty);
    });
  });

  group('a copy that cannot be read', () {
    for (final refuseZip in [true, false]) {
      test('is "unreadable", and the copy is removed '
          '(refuseZip: $refuseZip)', () async {
        picker.willPick(json);
        reader.failing = true;
        final result = await pick(refuseZip: refuseZip);

        expect(
          (result as PickedTextProblem).problem,
          PickedFileProblem.unreadable,
        );
        expect(picker.discarded, hasLength(1));
        expect(picker.copiesOnDisk(), isEmpty);
      });
    }

    test('a copy above the cap is "unreadable", never half a file', () async {
      // The picker never hands out such a copy. If it did, the read's own
      // count would still refuse it.
      picker.willPick(List<int>.filled(1001, 0x20));
      final result = await pick(refuseZip: false);
      expect(
        (result as PickedTextProblem).problem,
        PickedFileProblem.unreadable,
      );
      expect(picker.copiesOnDisk(), isEmpty);
    });

    for (final refuseZip in [true, false]) {
      test('a reader that throws: the copy is removed all the same '
          '(refuseZip: $refuseZip)', () async {
        picker.willPick(json);
        await expectLater(
          pickAndReadText(
            picker: picker,
            reader: _ThrowingReader(),
            maxBytes: 1000,
            refuseZip: refuseZip,
          ),
          throwsStateError,
        );
        expect(picker.discarded, hasLength(1));
        expect(picker.copiesOnDisk(), isEmpty);
      });
    }
  });
}
