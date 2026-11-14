/// Review finding M05: a file must be read under a byte cap that is enforced
/// on the bytes that ACTUALLY arrive, not on the size somebody reports.
library;

import 'dart:io';

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

  group('readFileBounded', () {
    test('reads a file that fits exactly (cap is inclusive)', () async {
      final f = write('fit.bin', List<int>.generate(1000, (i) => i % 256));
      final out = await readFileBounded(f.path, maxBytes: 1000);
      expect(out, isNotNull);
      expect(out!.length, 1000);
      expect(out[999], 999 % 256);
    });

    test('returns null for a file one byte over the cap', () async {
      final f = write('over.bin', List<int>.filled(1001, 7));
      expect(await readFileBounded(f.path, maxBytes: 1000), isNull);
    });

    test('empty file reads as empty, not null', () async {
      final f = write('empty.bin', const []);
      final out = await readFileBounded(f.path, maxBytes: 10);
      expect(out, isNotNull);
      expect(out, isEmpty);
    });

    test('a file of several blocks is counted across blocks', () async {
      // dart:io streams files in 64 KiB blocks; 200 KiB crosses several.
      final f = write('chunks.bin', List<int>.filled(200 * 1024, 3));
      expect(await readFileBounded(f.path, maxBytes: 150 * 1024), isNull);
      final ok = await readFileBounded(f.path, maxBytes: 200 * 1024);
      expect(ok!.length, 200 * 1024);
    });

    test('a file of several blocks comes back byte for byte', () async {
      // Every position has its own value (251 is a prime, so the pattern
      // does not repeat with the 64 KiB blocks). A block that was handed
      // out twice, or put in the wrong place, would show here.
      final bytes = List<int>.generate(200 * 1024 + 17, (i) => i % 251);
      final f = write('pattern.bin', bytes);
      final out = await readFileBounded(f.path, maxBytes: bytes.length);
      expect(out, bytes);
    });

    test('the bytes are a list of their own, not a window into a larger '
        'buffer', () async {
      // Code further on may look at `.buffer`. It must then see these
      // bytes and nothing else, for a file of one block and of several.
      for (final size in [10, 200 * 1024 + 17]) {
        final f = write('own_$size.bin', List<int>.filled(size, 9));
        final out = (await readFileBounded(f.path, maxBytes: size))!;
        expect(out.offsetInBytes, 0, reason: '$size bytes');
        expect(out.buffer.lengthInBytes, size, reason: '$size bytes');
      }
    });

    test('a file that is not there throws, it is not "too large"', () async {
      await expectLater(
        readFileBounded('${tmp.path}/missing.bin', maxBytes: 10),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('readBounded: a length that is wrong in either direction', () {
    test('a length above the cap is refused, and the source is never '
        'opened', () async {
      // 3 bytes that claim to be 5 GiB. Only the announced length can
      // refuse them, and it must do so before anything is read.
      var opened = false;
      final out = await readBounded(
        length: () async => 5 * 1024 * 1024 * 1024,
        open: () {
          opened = true;
          return Stream.value([1, 2, 3]);
        },
        maxBytes: 1024,
      );
      expect(out, isNull);
      expect(opened, isFalse);
    });

    test('a length that is too SMALL does not help: the count while '
        'reading refuses', () async {
      // 10 bytes are announced; 5,000 arrive.
      final out = await readBounded(
        length: () async => 10,
        open: () => Stream.value(List<int>.filled(5000, 1)),
        maxBytes: 1024,
      );
      expect(out, isNull);
    });

    test('an honest source within the cap is read', () async {
      final out = await readBounded(
        length: () async => 3,
        open: () => Stream.value([1, 2, 3]),
        maxBytes: 3,
      );
      expect(out, [1, 2, 3]);
    });
  });

  group('collectBounded', () {
    Stream<List<int>> blocks(List<int> sizes) =>
        Stream.fromIterable([for (final n in sizes) List<int>.filled(n, 1)]);

    test('gathers the blocks in order', () async {
      final out = await collectBounded(
        Stream.fromIterable([
          [1, 2],
          <int>[],
          [3],
        ]),
        maxBytes: 3,
      );
      expect(out, [1, 2, 3]);
    });

    test('more bytes than the cap in the FIRST block: null', () async {
      // Nobody announced a length here: only the count while the bytes
      // arrive can refuse.
      expect(await collectBounded(blocks([5000]), maxBytes: 1024), isNull);
    });

    test('the cap is passed in a LATER block: null, and the rest is not '
        'read', () async {
      // Fifty blocks stand for "far more than the cap". (Not a stream
      // without end: with the count switched off this test would then
      // never finish instead of failing.)
      var asked = 0;
      Stream<List<int>> long() async* {
        for (var i = 0; i < 50; i++) {
          asked++;
          yield List<int>.filled(400, 1);
        }
      }

      // 400 + 400 fit under 1,000; the third block does not.
      expect(await collectBounded(long(), maxBytes: 1000), isNull);
      expect(asked, 3, reason: 'what lies behind the cap must not be read');
    });

    test('exactly the cap is accepted', () async {
      final out = await collectBounded(blocks([400, 600]), maxBytes: 1000);
      expect(out!.length, 1000);
    });

    test('an empty stream is an empty list, not null', () async {
      final out = await collectBounded(
        const Stream<List<int>>.empty(),
        maxBytes: 10,
      );
      expect(out, isNotNull);
      expect(out, isEmpty);
    });
  });
}
