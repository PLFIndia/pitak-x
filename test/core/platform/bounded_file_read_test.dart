/// M05 (astra-review.md): picked files must be read under a byte cap that is
/// enforced on the bytes that ACTUALLY arrive, not on the size the picker
/// reports.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/bounded_file_read.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bounded_file_read_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  group('readPickedFileBounded', () {
    test('reads a file that fits exactly (cap is inclusive)', () async {
      final f = write('fit.bin', List<int>.generate(1000, (i) => i % 256));
      final out = await readPickedFileBounded(XFile(f.path), maxBytes: 1000);
      expect(out, isNotNull);
      expect(out!.length, 1000);
      expect(out[999], 999 % 256);
    });

    test('returns null for a file one byte over the cap', () async {
      final f = write('over.bin', List<int>.filled(1001, 7));
      expect(
        await readPickedFileBounded(XFile(f.path), maxBytes: 1000),
        isNull,
      );
    });

    test('rejects on the reported length without opening the file', () async {
      // XFile.fromData with a LYING length: the data is 3 bytes but the
      // picker claims 5 GiB. Must be rejected purely on the report — an
      // implementation that tried to buffer 5 GiB here would fail.
      final lying = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        length: 5 * 1024 * 1024 * 1024,
      );
      expect(await readPickedFileBounded(lying, maxBytes: 1024), isNull);
    });

    test('rejects on ACTUAL bytes when reported length lies small', () async {
      // The picker claims 10 bytes; the stream delivers 5000. The running
      // count must catch it — length() alone is not the guarantee.
      final lying = XFile.fromData(
        Uint8List.fromList(List<int>.filled(5000, 1)),
        length: 10,
      );
      expect(await readPickedFileBounded(lying, maxBytes: 1024), isNull);
    });

    test('an in-memory XFile within the cap reads back intact', () async {
      final data = Uint8List.fromList(List<int>.generate(300, (i) => i));
      final out = await readPickedFileBounded(
        XFile.fromData(data),
        maxBytes: 300,
      );
      expect(out, data);
    });

    test('empty file reads as empty, not null', () async {
      final f = write('empty.bin', const []);
      final out = await readPickedFileBounded(XFile(f.path), maxBytes: 10);
      expect(out, isNotNull);
      expect(out, isEmpty);
    });

    test('a real multi-chunk file is counted across chunks', () async {
      // dart:io streams files in 64 KiB chunks; 200 KiB crosses several.
      final f = write('chunks.bin', List<int>.filled(200 * 1024, 3));
      expect(
        await readPickedFileBounded(XFile(f.path), maxBytes: 150 * 1024),
        isNull,
      );
      final ok = await readPickedFileBounded(
        XFile(f.path),
        maxBytes: 200 * 1024,
      );
      expect(ok!.length, 200 * 1024);
    });
  });
}
