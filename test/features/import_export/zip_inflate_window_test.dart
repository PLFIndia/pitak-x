import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Inflate, InputMemoryStream, getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/infrastructure/zip_inflate_window.dart';

/// The two classes between `package:archive`'s inflater and a file, alone
/// (backup rework BR5): `ZipWindowSink`, which keeps only the last 32 KiB of
/// the output, and `ZipFileRangeInput`, which reads one range of a file
/// through a small buffer.
///
/// WHY (beginner note): these two decide whether a hostile archive can make
/// the app use more memory than it has, and whether an honest one comes out
/// right. They are tested here without a ZIP around them: a raw deflate
/// stream in a file, in and out, compared byte for byte.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('zip_inflate_window_test');
  });
  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  /// Test data of several kinds. Each stresses another part of the sink.
  Uint8List payload(String kind, int size, Random random) {
    final out = Uint8List(size);
    switch (kind) {
      case 'random': // does not compress: literal bytes
        for (var i = 0; i < size; i++) {
          out[i] = random.nextInt(256);
        }
      case 'zeros': // the longest repeats, each overlapping itself
        break;
      case 'words': // many short repeats from near by
        const words = ['pitak', 'book', 'cover', 'loan', 'the', 'of'];
        var i = 0;
        while (i < size) {
          final word = words[random.nextInt(words.length)];
          for (var j = 0; j < word.length && i < size; j++) {
            out[i++] = word.codeUnitAt(j);
          }
          if (i < size) out[i++] = 0x20;
        }
      case 'pages': // like a database: a header, rows, empty space
        for (var i = 0; i < size; i++) {
          final inPage = i % 4096;
          out[i] = inPage < 100
              ? (inPage * 7) & 0xFF
              : inPage < 3000
              ? 0x20 + random.nextInt(40)
              : 0;
        }
      case 'far': // one 30 KiB block again and again: repeats from far back
        final block = Uint8List(30000);
        for (var i = 0; i < block.length; i++) {
          block[i] = random.nextInt(256);
        }
        for (var i = 0; i < size; i++) {
          out[i] = block[i % block.length];
        }
    }
    return out;
  }

  /// Writes [bytes] to a file with 777 bytes in front and 333 behind, so a
  /// read outside the range would show, and opens it.
  ({RandomAccessFile file, ZipFileSource source, int start}) fileWith(
    List<int> bytes,
  ) {
    final path = '${folder.path}/stream.bin';
    File(path).writeAsBytesSync([
      ...List<int>.filled(777, 0xEE),
      ...bytes,
      ...List<int>.filled(333, 0xDD),
    ]);
    final file = File(path).openSync();
    return (
      file: file,
      source: ZipFileSource(file, file.lengthSync()),
      start: 777,
    );
  }

  /// Inflates [stream] from a file through the two classes.
  ({Uint8List bytes, int crc, bool finished, int produced, int largestChunk})
  inflate(
    List<int> stream, {
    required int budget,
    int inputBuffer = ZipFileRangeInput.defaultBufferBytes,
    int pending = ZipWindowSink.defaultPendingBytes,
  }) {
    final opened = fileWith(stream);
    try {
      final out = BytesBuilder();
      var crc = 0;
      var largestChunk = 0;
      final sink = ZipWindowSink(
        budget: budget,
        pendingBytes: pending,
        onChunk: (chunk) {
          crc = getCrc32(chunk, crc);
          out.add(chunk);
          if (chunk.length > largestChunk) largestChunk = chunk.length;
        },
      );
      final inflater = Inflate.stream(
        ZipFileRangeInput(
          opened.source,
          opened.start,
          stream.length,
          bufferBytes: inputBuffer,
        ),
        output: sink,
      );
      sink.finish();
      return (
        bytes: out.takeBytes(),
        crc: crc,
        finished: inflater.isFinished,
        produced: sink.length,
        largestChunk: largestChunk,
      );
    } finally {
      opened.file.closeSync();
    }
  }

  group('honest streams come out byte for byte', () {
    // Sizes right at the edges of the window (32 KiB) and of the pending
    // area (64 KiB), and a few that cross them several times.
    const sizes = [0, 1, 2, 257, 32767, 32768, 32769, 65536, 98304, 300000];
    // Level 0 writes blocks WITHOUT compression (another write path of the
    // sink); 1, 6 and 9 choose repeats differently.
    const levels = [0, 1, 6, 9];
    // (input buffer, pending area): the app's sizes, and tiny ones that
    // push a buffer edge through nearly every byte.
    const shapes = [(65536, 65536), (16, 300)];

    for (final kind in ['random', 'zeros', 'words', 'pages', 'far']) {
      test('$kind: ${sizes.length} sizes × ${levels.length} levels × '
          '${shapes.length} buffer shapes', () {
        final random = Random(20261111);
        for (final size in sizes) {
          final data = payload(kind, size, random);
          for (final level in levels) {
            final stream = ZLibEncoder(raw: true, level: level).convert(data);
            for (final (inputBuffer, pending) in shapes) {
              final got = inflate(
                stream,
                budget: size,
                inputBuffer: inputBuffer,
                pending: pending,
              );
              final what =
                  '$kind, $size bytes, level $level, '
                  'buffers $inputBuffer/$pending';
              expect(got.finished, isTrue, reason: what);
              expect(got.produced, size, reason: what);
              expect(got.crc, getCrc32(data), reason: what);
              expect(got.bytes, data, reason: what);
              // The sink never hands on more than it may hold: the window
              // plus the pending area (at least one longest repeat).
              expect(
                got.largestChunk,
                lessThanOrEqualTo(ZipWindowSink.window + max(pending, 258)),
                reason: what,
              );
            }
          }
        }
      });
    }

    test('3 MB of pages: the window moves many times and nothing is lost', () {
      final data = payload('pages', 3000000, Random(7));
      final got = inflate(
        ZLibEncoder(raw: true).convert(data),
        budget: 3000000,
      );
      expect(got.finished, isTrue);
      expect(got.bytes, data);
      expect(
        got.largestChunk,
        lessThanOrEqualTo(
          ZipWindowSink.window + ZipWindowSink.defaultPendingBytes,
        ),
      );
    });

    test('bytes behind the end mark, inside the range, are not read as '
        'content', () {
      final data = payload('words', 5000, Random(1));
      final got = inflate([
        ...ZLibEncoder(raw: true).convert(data),
        9,
        9,
        9,
        9,
      ], budget: 5000);
      expect(got.finished, isTrue);
      expect(got.bytes, data);
    });
  });

  group('the budget stops every way the inflater writes', () {
    Matcher stoppedAt(int most) => throwsA(
      isA<ZipBudgetExceeded>().having(
        (e) => e.attempted,
        'attempted',
        greaterThan(most),
      ),
    );

    test('repeats: 64 MiB of zeros in 65 KB, with a budget of 512 bytes', () {
      final bomb = ZLibEncoder(
        raw: true,
        level: 9,
      ).convert(Uint8List(64 * 1024 * 1024));
      expect(bomb.length, lessThan(100 * 1024));
      var handedOn = 0;
      final opened = fileWith(bomb);
      try {
        final sink = ZipWindowSink(
          budget: 512,
          onChunk: (chunk) => handedOn += chunk.length,
        );
        expect(
          () => Inflate.stream(
            ZipFileRangeInput(opened.source, opened.start, bomb.length),
            output: sink,
          ),
          stoppedAt(512),
        );
        // Refused BEFORE the write: the count never passed the budget, and
        // nothing was handed on that was not counted.
        expect(sink.length, lessThanOrEqualTo(512));
        expect(sink.length, greaterThan(0));
        sink.finish();
        expect(handedOn, sink.length);
      } finally {
        opened.file.closeSync();
      }
    });

    test('data that does not compress, packed at level 6', () {
      final data = payload('random', 5000, Random(3));
      expect(
        () => inflate(ZLibEncoder(raw: true).convert(data), budget: 4999),
        stoppedAt(4999),
      );
    });

    test('blocks without compression (level 0)', () {
      final data = payload('random', 5000, Random(3));
      expect(
        () => inflate(
          ZLibEncoder(raw: true, level: 0).convert(data),
          budget: 4999,
        ),
        stoppedAt(4999),
      );
    });

    test('exactly at the budget is fine, for each of the three', () {
      for (final (kind, level) in [
        ('zeros', 9),
        ('random', 6),
        ('random', 0),
      ]) {
        final data = payload(kind, 5000, Random(3));
        final got = inflate(
          ZLibEncoder(raw: true, level: level).convert(data),
          budget: 5000,
        );
        expect(got.bytes, data, reason: '$kind level $level');
      }
    });

    test('a budget of nothing: an empty stream passes, one byte does not', () {
      // One empty block, flagged "last": how `archive` 3 wrote no content.
      final empty = inflate([3, 0], budget: 0);
      expect(empty.finished, isTrue);
      expect(empty.produced, 0);
      expect(
        () => inflate(ZLibEncoder(raw: true).convert([7]), budget: 0),
        stoppedAt(0),
      );
    });
  });

  group('damaged streams are seen', () {
    test('a stream without its end mark comes back "not finished"', () {
      // One block that is not marked as the last, then a block type that
      // no deflate stream may hold.
      final got = inflate([
        0x00,
        5,
        0,
        0xFA,
        0xFF,
        1,
        2,
        3,
        4,
        5,
        0x06,
      ], budget: 100);
      expect(got.finished, isFalse);
      expect(got.bytes, [1, 2, 3, 4, 5]);
    });

    test('a stream cut short comes back "not finished"', () {
      final data = payload('words', 50000, Random(1));
      final stream = ZLibEncoder(raw: true).convert(data);
      final got = inflate(stream.sublist(0, stream.length - 6), budget: 50000);
      expect(got.finished, isFalse);
      expect(got.produced, lessThan(50000));
    });

    test('a repeat as the very first thing: nothing to repeat from', () {
      // "Copy 3 bytes from 1 byte back" when nothing was written yet.
      final got = inflate(const [0x03, 0x02, 0x00], budget: 100);
      expect(got.finished, isFalse);
      expect(got.produced, 0);
    });

    test('an empty range is not a stream', () {
      final got = inflate(const [], budget: 100);
      expect(got.finished, isFalse);
      expect(got.produced, 0);
    });
  });

  group('ZipWindowSink, called directly', () {
    ZipWindowSink sinkInto(BytesBuilder out, {int budget = 1 << 20}) =>
        ZipWindowSink(budget: budget, onChunk: out.add);

    test('a repeat must reach into what was written, at most 32 KiB back '
        '(the sink checks by itself; the inflater checks too)', () {
      final out = BytesBuilder();
      final sink = sinkInto(out);
      // Nothing written yet: nothing to repeat.
      expect(() => sink.writeBackReference(1, 3), throwsFormatException);
      // A distance of zero would never move on.
      sink.writeBytes(List<int>.generate(40000, (i) => i & 0xFF));
      expect(() => sink.writeBackReference(0, 3), throwsFormatException);
      expect(() => sink.writeBackReference(-1, 3), throwsFormatException);
      // Further back than what was written, and further than the window.
      expect(() => sink.writeBackReference(40001, 3), throwsFormatException);
      expect(() => sink.writeBackReference(32769, 3), throwsFormatException);
      // A refused repeat wrote nothing and counted nothing.
      expect(sink.length, 40000);

      // Exactly the window is allowed, and gives the right bytes: byte
      // 40000 - 32768 = 7232 and the two after it.
      sink
        ..writeBackReference(32768, 3)
        ..finish();
      final bytes = out.takeBytes();
      expect(bytes.length, 40003);
      expect(bytes.sublist(40000), [7232 & 0xFF, 7233 & 0xFF, 7234 & 0xFF]);
    });

    test('a repeat longer than deflate allows is refused', () {
      final sink = sinkInto(BytesBuilder())..writeByte(1);
      expect(
        () => sink.writeBackReference(1, ZipWindowSink.defaultPendingBytes + 1),
        throwsFormatException,
      );
      expect(() => sink.writeBackReference(1, -1), throwsFormatException);
    });

    test('a repeat that overlaps itself repeats the pattern', () {
      final out = BytesBuilder();
      sinkInto(out)
        ..writeBytes([1, 2, 3])
        ..writeBackReference(3, 8) // 1 2 3 1 2 3 1 2
        ..writeBackReference(1, 2) // 2 2
        ..finish();
      expect(out.takeBytes(), [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 2, 2]);
    });

    test('every way to write is counted and guarded: also the ones the '
        'inflater does not use', () {
      final out = BytesBuilder();
      final sink = sinkInto(out, budget: 12)
        ..writeByte(1)
        ..writeBytes([2, 3, 4], length: 2)
        ..writeStream(InputMemoryStream(Uint8List.fromList([5, 6])))
        ..writeRange(Uint8List.fromList([0, 7, 8, 0]), 1, 3)
        ..writeUint16(0x0A09)
        ..writeBackReference(2, 1); // 9
      expect(sink.length, 10);
      expect(() => sink.writeUint32(0), throwsA(isA<ZipBudgetExceeded>()));
      expect(
        () => sink.writeBytes([1, 2, 3]),
        throwsA(isA<ZipBudgetExceeded>()),
      );
      expect(
        () => sink.writeStream(InputMemoryStream(Uint8List(3))),
        throwsA(isA<ZipBudgetExceeded>()),
      );
      expect(
        () => sink.writeBackReference(1, 3),
        throwsA(isA<ZipBudgetExceeded>()),
      );
      // `writeUint32` got two of its four bytes out before the third was
      // refused: each byte is guarded on its own.
      expect(sink.length, 12);
      expect(() => sink.writeByte(1), throwsA(isA<ZipBudgetExceeded>()));
      sink.finish();
      expect(out.takeBytes(), [1, 2, 3, 5, 6, 7, 8, 9, 10, 9, 0, 0]);
    });

    test('what was produced cannot be read back, and the count cannot be '
        'moved', () {
      final sink = sinkInto(BytesBuilder())..writeBytes([1, 2, 3]);
      expect(sink.getBytes, throwsStateError);
      expect(() => sink.subset(0), throwsStateError);
      expect(sink.clear, throwsStateError);
      expect(sink.reset, throwsStateError);
      // Announcing a size allocates nothing and changes nothing.
      sink
        ..reserve(1 << 40)
        ..flush();
      expect(sink.length, 3);
    });

    test('`finish` hands on the rest once; a second call adds nothing', () {
      final chunks = <List<int>>[];
      final sink = ZipWindowSink(
        budget: 100,
        onChunk: (chunk) => chunks.add(chunk.toList()),
      )..writeBytes([1, 2, 3]);
      expect(chunks, isEmpty, reason: 'still pending');
      sink
        ..finish()
        ..finish();
      expect(chunks, [
        [1, 2, 3],
      ]);
    });

    test('a pending area smaller than the longest repeat is made large '
        'enough for one', () {
      final out = BytesBuilder();
      ZipWindowSink(budget: 1000, pendingBytes: 1, onChunk: out.add)
        ..writeByte(7)
        ..writeBackReference(1, 258)
        ..finish();
      expect(out.takeBytes(), List<int>.filled(259, 7));
    });
  });

  group('ZipFileRangeInput, called directly', () {
    final content = List<int>.generate(1000, (i) => (i * 3) & 0xFF);

    test('reads the range and nothing around it, through a tiny buffer, '
        'with steps back in between', () {
      final opened = fileWith(content);
      try {
        final input = ZipFileRangeInput(
          opened.source,
          opened.start,
          content.length,
          bufferBytes: 16,
        );
        expect(input.length, 1000);
        expect(input.totalLength, 1000);
        final read = <int>[];
        var nextStepBack = 37;
        while (!input.isEOS) {
          read.add(input.readByte());
          // Every 37 bytes, step back three and read them again: what the
          // inflater does at the end of a block. (Once per place, or the
          // loop would never get past it.)
          if (read.length == nextStepBack) {
            nextStepBack += 37;
            input.rewind(3);
            read.removeRange(read.length - 3, read.length);
          }
        }
        expect(read, content);
        expect(input.position, 1000);
        expect(input.length, 0);
        // At the end there is nothing more, and asking is an error.
        expect(input.readByte, throwsRangeError);
        input.reset();
        expect(input.readByte(), content.first);
      } finally {
        opened.file.closeSync();
      }
    });

    test('the position cannot leave the range', () {
      final opened = fileWith(content);
      try {
        final input = ZipFileRangeInput(opened.source, opened.start, 1000);
        expect(input.rewind, throwsRangeError);
        expect(() => input.skip(1001), throwsRangeError);
        expect(() => input.setPosition(-1), throwsRangeError);
        input
          ..skip(1000)
          ..position = 998;
        expect(input.readByte(), content[998]);
      } finally {
        opened.file.closeSync();
      }
    });

    test('a piece for a block without compression: a copy, clamped to '
        'the range, never more than such a block can hold', () {
      final large = List<int>.generate(70000, (i) => (i * 5) & 0xFF);
      final opened = fileWith(large);
      try {
        final input = ZipFileRangeInput(opened.source, opened.start, 70000)
          ..skip(10);
        // `readBytes` is what the inflater calls: a piece from the read
        // position, and the position moves on.
        expect(input.readBytes(5).toUint8List(), large.sublist(10, 15));
        expect(input.position, 15);
        // `subset` does not move the position.
        expect(
          input.subset(position: 100, length: 4).toUint8List(),
          large.sublist(100, 104),
        );
        expect(input.position, 15);
        // The longest block deflate allows.
        expect(
          input.subset(position: 0, length: 0xFFFF).toUint8List(),
          large.sublist(0, 0xFFFF),
        );
        // More than that is never asked by the inflater, and is refused
        // instead of allocated.
        expect(
          () => input.subset(position: 0, length: 0x10000),
          throwsStateError,
        );
        expect(() => input.subset(position: 0), throwsStateError);
        // A length beyond the range is clamped to the range: the bytes
        // behind the range (0xDD) never show.
        expect(
          input.subset(position: 69990, length: 500).toUint8List(),
          large.sublist(69990),
        );
        expect(() => input.subset(position: 70001), throwsRangeError);
        expect(input.toUint8List, throwsUnsupportedError);
      } finally {
        opened.file.closeSync();
      }
    });

    test('a range at the very end of the file is read to its last byte', () {
      final path = '${folder.path}/end.bin';
      File(path).writeAsBytesSync([9, 9, 9, ...content]);
      final file = File(path).openSync();
      try {
        final input = ZipFileRangeInput(
          ZipFileSource(file, file.lengthSync()),
          3,
          1000,
          bufferBytes: 64,
        );
        final read = [for (var i = 0; i < 1000; i++) input.readByte()];
        expect(read, content);
        expect(input.isEOS, isTrue);
      } finally {
        file.closeSync();
      }
    });
  });

  group('ZipFileSource', () {
    test('a file that got shorter after it was opened refuses the archive', () {
      final path = '${folder.path}/cut.bin';
      File(path).writeAsBytesSync(List<int>.filled(5000, 1));
      final file = File(path).openSync();
      try {
        final source = ZipFileSource(file, file.lengthSync());
        expect(source.read(4000, 1000), List<int>.filled(1000, 1));
        // Someone cuts the file while it is open.
        File(path).writeAsBytesSync(List<int>.filled(4500, 1));
        expect(
          () => source.read(4000, 1000),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('changed while it was being read'),
            ),
          ),
        );
        // And through the inflater's input, which reads in buffers.
        final input = ZipFileRangeInput(source, 4000, 1000, bufferBytes: 64);
        final read = <int>[];
        expect(() {
          while (!input.isEOS) {
            read.add(input.readByte());
          }
        }, throwsA(isA<BoundedExtractionException>()));
        // It stopped at the cut, without making up a single byte.
        expect(read.length, lessThanOrEqualTo(500));
        expect(read, everyElement(1));
      } finally {
        file.closeSync();
      }
    });

    test('a range outside the file as it was opened is never read', () {
      final path = '${folder.path}/small.bin';
      File(path).writeAsBytesSync(List<int>.filled(100, 1));
      final file = File(path).openSync();
      try {
        final source = ZipFileSource(file, 100);
        for (final (offset, count) in [(-1, 1), (0, 101), (100, 1), (50, -1)]) {
          expect(
            () => source.read(offset, count),
            throwsA(isA<BoundedExtractionException>()),
            reason: '$offset, $count',
          );
          expect(
            () => source.readInto(Uint8List(200), offset, count),
            throwsA(isA<BoundedExtractionException>()),
            reason: '$offset, $count',
          );
        }
        // The edges themselves are fine.
        expect(source.read(0, 100), hasLength(100));
        expect(source.read(100, 0), isEmpty);
      } finally {
        file.closeSync();
      }
    });
  });
}
