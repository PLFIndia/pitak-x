import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

import 'hostile_zip_builder.dart';

/// `BoundedZipFile`, the ZIP reader that works from a file (backup rework
/// BR5): what only THIS reader does.
///
/// WHY (beginner note): what a reader decides about a ZIP file's structure
/// is tested for both readers at once, in `bounded_zip_extractor_test.dart`
/// and `bounded_zip_extractor_container_test.dart`. This file is about the
/// rest: taking one entry at a time, into memory or into a file; what
/// happens to a half-written file; a file that changes while it is read;
/// and entries that are left out or ignored because of their rule.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('bounded_zip_file_test');
  });
  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  final roomy = ZipLimits(
    maxEntryBytes: 512 * 1024,
    maxTotalBytes: 1024 * 1024,
    maxEntries: 16,
    maxArchiveBytes: 2 * 1024 * 1024,
  );

  /// Writes [zip] into the test's folder and gives its path.
  String onDisk(Uint8List zip, {String name = 'archive.zip'}) {
    final path = '${folder.path}/$name';
    File(path).writeAsBytesSync(zip);
    return path;
  }

  Matcher refusedWith(String part) => throwsA(
    isA<BoundedExtractionException>().having(
      (e) => e.message,
      'message',
      contains(part),
    ),
  );

  List<String> namesInFolder() => [
    for (final entity in folder.listSync())
      entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
  ]..sort();

  final words = Uint8List.fromList(
    List<int>.generate(300000, (i) => 'pitak book cover '.codeUnitAt(i % 17)),
  );
  final noise = Uint8List.fromList(
    List<int>.generate(70000, (i) => Random(i).nextInt(256)),
  );

  group('open', () {
    test('lists every entry in the order of the directory, with what it '
        'declares, and unpacks nothing', () {
      var probeCalls = 0;
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('manifest.json', [1, 2, 3]),
            HostileEntry('some/dir/words.txt', words),
            HostileEntry('noise.bin', noise, deflate: false),
            HostileEntry('empty', const []),
          ]),
        ),
        limits: roomy,
        unpackedBytesProbe: (_) => probeCalls++,
      );
      addTearDown(file.close);
      expect(
        [for (final e in file.entries) (e.name, e.size, e.verdict)],
        [
          ('manifest.json', 3, ZipEntryVerdict.take),
          ('words.txt', 300000, ZipEntryVerdict.take),
          ('noise.bin', 70000, ZipEntryVerdict.take),
          ('empty', 0, ZipEntryVerdict.take),
        ],
      );
      expect(file.entry('noise.bin'), same(file.entries[2]));
      expect(file.entry('some/dir/words.txt'), isNull, reason: 'leaf only');
      expect(file.entry('nothing'), isNull);
      expect(probeCalls, 0);
    });

    test('without limits it uses those of a Pitak backup', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('a', [1]),
          ]),
        ),
      );
      addTearDown(file.close);
      expect(file.entries.single.name, 'a');
    });

    test('a file that is not there, or is a folder, is trouble with the '
        'disk, not a damaged archive', () {
      expect(
        () => BoundedZipFile.open('${folder.path}/missing.zip'),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        () => BoundedZipFile.open(folder.path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('an archive longer than the last-bytes search, with a comment: '
        'the end record and the directory are found', () {
      final path = onDisk(
        buildHostileZip([
          HostileEntry('noise.bin', noise, deflate: false),
          HostileEntry('words.txt', words),
        ], eocdComment: List<int>.filled(300, 0x41)),
      );
      expect(File(path).lengthSync(), greaterThan(22 + 0xFFFF));
      final file = BoundedZipFile.open(path, limits: roomy);
      addTearDown(file.close);
      expect(file.read(file.entry('words.txt')!, maxBytes: 300000), words);
    });

    test('EVERY cut of a valid archive gives a typed refusal or a correct '
        'entry, never a crash and never wrong content', () {
      final good = buildHostileZip(
        [
          HostileEntry('a', List<int>.generate(64, (i) => i)),
          HostileEntry(
            'b',
            List<int>.generate(300, (i) => i % 251),
            deflate: false,
          ),
          HostileEntry(
            'c',
            List<int>.generate(90, (i) => i),
            dataDescriptor: true,
          ),
        ],
        eocdComment: [1, 2, 3],
      );
      final expected = {
        'a': List<int>.generate(64, (i) => i),
        'b': List<int>.generate(300, (i) => i % 251),
        'c': List<int>.generate(90, (i) => i),
      };
      var opened = 0;
      for (var cut = 0; cut <= good.length; cut++) {
        final path = onDisk(Uint8List.sublistView(good, 0, cut));
        try {
          final file = BoundedZipFile.open(path, limits: roomy);
          opened++;
          try {
            for (final entry in file.entries) {
              expect(
                file.read(entry, maxBytes: 1000),
                expected[entry.name],
                reason: 'cut at $cut, ${entry.name}',
              );
            }
          } finally {
            file.close();
          }
        } on BoundedExtractionException {
          // expected for nearly every cut
        }
        // Any other throw type leaves the loop and fails the test.
      }
      // The whole file opens, and so does the file without the last bytes
      // of its comment: the search then finds no record whose comment fits
      // and refuses. So exactly one length opens.
      expect(opened, 1);
    });

    test('EVERY single changed byte gives a typed refusal or the right '
        'content', () {
      final good = buildHostileZip([
        HostileEntry('a', List<int>.generate(64, (i) => i)),
        HostileEntry(
          'b',
          List<int>.generate(300, (i) => i % 251),
          deflate: false,
        ),
      ]);
      var refused = 0;
      for (var i = 0; i < good.length; i++) {
        final bad = Uint8List.fromList(good)..[i] ^= 0xFF;
        try {
          final file = BoundedZipFile.open(onDisk(bad), limits: roomy);
          try {
            for (final entry in file.entries) {
              final content = file.read(entry, maxBytes: 1000);
              // What does come out is covered by its checksum and its
              // declared size, whatever name the changed byte gave it.
              expect(content.length, entry.size, reason: 'byte $i');
            }
          } finally {
            file.close();
          }
        } on BoundedExtractionException {
          refused++;
        }
      }
      // Most bytes of a ZIP matter. (Some do not: times, dates, versions,
      // attributes.)
      expect(refused, greaterThan(good.length ~/ 2));
    });
  });

  group('read: an entry into memory', () {
    test('deflated, stored and empty entries come out byte for byte, in '
        'any order and more than once', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('words.txt', words),
            HostileEntry('noise.bin', noise, deflate: false),
            HostileEntry('empty.stored', const [], deflate: false),
            HostileEntry('empty.deflated', const []),
            HostileEntry('late.sizes', words, dataDescriptor: true),
          ]),
        ),
        limits: roomy,
      );
      addTearDown(file.close);
      Uint8List read(String name) =>
          file.read(file.entry(name)!, maxBytes: roomy.maxEntryBytes);
      expect(read('late.sizes'), words);
      expect(read('noise.bin'), noise);
      expect(read('words.txt'), words);
      expect(read('empty.stored'), isEmpty);
      expect(read('empty.deflated'), isEmpty);
      expect(read('noise.bin'), noise, reason: 'a second time');
    });

    test('the result is a list of exactly the entry, not a view into '
        'something larger', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('small', List<int>.filled(700, 3)),
            HostileEntry('large', words),
          ]),
        ),
        limits: roomy,
      );
      addTearDown(file.close);
      for (final entry in file.entries) {
        final out = file.read(entry, maxBytes: roomy.maxEntryBytes);
        expect(out.length, entry.size);
        expect(out.offsetInBytes, 0);
        expect(out.buffer.lengthInBytes, entry.size);
      }
    });

    test('an entry that declares more than the caller allows is refused '
        'before it is unpacked; exactly the allowed size is read', () {
      var probeCalls = 0;
      final file = BoundedZipFile.open(
        onDisk(buildHostileZip([HostileEntry('words.txt', words)])),
        limits: roomy,
        unpackedBytesProbe: (_) => probeCalls++,
      );
      addTearDown(file.close);
      final entry = file.entries.single;
      expect(
        () => file.read(entry, maxBytes: words.length - 1),
        refusedWith("'words.txt' is too large to be read into memory"),
      );
      expect(probeCalls, 0);
      expect(file.read(entry, maxBytes: words.length), words);
      expect(probeCalls, 1);
    });
  });

  group('writeTo: an entry into a file', () {
    test('deflated, stored and empty entries arrive byte for byte', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('words.txt', words),
            HostileEntry('noise.bin', noise, deflate: false),
            HostileEntry('empty', const []),
          ]),
        ),
        limits: roomy,
      );
      addTearDown(file.close);
      for (final (name, content) in [
        ('words.txt', words),
        ('noise.bin', noise),
        ('empty', Uint8List(0)),
      ]) {
        final target = '${folder.path}/out_$name';
        file.writeTo(file.entry(name)!, target);
        expect(File(target).readAsBytesSync(), content, reason: name);
      }
    });

    test('an existing file is never replaced: the call fails and the file '
        'is as it was', () {
      final file = BoundedZipFile.open(
        onDisk(buildHostileZip([HostileEntry('words.txt', words)])),
        limits: roomy,
      );
      addTearDown(file.close);
      final target = File('${folder.path}/taken')..writeAsStringSync('mine');
      expect(
        () => file.writeTo(file.entries.single, target.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.readAsStringSync(), 'mine');
    });

    test('a folder that is not there is trouble with the disk, and nothing '
        'is created', () {
      final file = BoundedZipFile.open(
        onDisk(buildHostileZip([HostileEntry('words.txt', words)])),
        limits: roomy,
      );
      addTearDown(file.close);
      expect(
        () => file.writeTo(
          file.entries.single,
          '${folder.path}/no/such/folder/out',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(namesInFolder(), ['archive.zip']);
    });

    test("the path is the caller's: an entry called like a path does not "
        'decide where it is written', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('../../../outside.txt', [1, 2, 3]),
          ]),
        ),
        limits: roomy,
      );
      addTearDown(file.close);
      final entry = file.entries.single;
      expect(entry.name, 'outside.txt');
      file.writeTo(entry, '${folder.path}/chosen_by_the_caller');
      expect(namesInFolder(), ['archive.zip', 'chosen_by_the_caller']);
    });

    // Each of these fails only AFTER content was written, so the file
    // existed with bytes in it when the failure came.
    final failures = <String, (HostileEntry, String)>{
      'a wrong checksum, found at the very end': (
        HostileEntry('e', words, declaredCrc32: 0x12345678),
        'failed its checksum',
      ),
      'more content than declared, found in the middle': (
        HostileEntry('e', words, declaredUncompressedSize: 200000),
        'holds more than the 200000 bytes it declares',
      ),
      'less content than declared': (
        HostileEntry('e', words, declaredUncompressedSize: 300001),
        'holds 300000 bytes, not the 300001 it declares',
      ),
      'a stream that stops without its end mark': (
        HostileEntry(
          'e',
          const [1, 2, 3, 4, 5],
          compressedOverride: const [
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
          ],
        ),
        'deflate stream has no end mark',
      ),
      'a stored entry with a wrong checksum': (
        HostileEntry('e', noise, deflate: false, declaredCrc32: 1),
        'failed its checksum',
      ),
    };
    for (final MapEntry(key: what, value: (entry, reason))
        in failures.entries) {
      test('$what: refused, and no half-written file stays', () {
        final file = BoundedZipFile.open(
          onDisk(
            buildHostileZip([
              HostileEntry('good', [1, 2, 3]),
              entry,
            ]),
          ),
          limits: roomy,
        );
        addTearDown(file.close);
        expect(
          () => file.writeTo(file.entry('e')!, '${folder.path}/out'),
          refusedWith(reason),
        );
        expect(namesInFolder(), ['archive.zip']);
        // `read` refuses the same entry for the same reason.
        expect(
          () => file.read(file.entry('e')!, maxBytes: roomy.maxEntryBytes),
          refusedWith(reason),
        );
        // The archive is still usable for its other entries.
        expect(file.read(file.entry('good')!, maxBytes: 10), [1, 2, 3]);
      });
    }
  });

  group('the size an entry declares is the size it has (rule N1)', () {
    test('a bomb that declares 512 bytes is stopped at 512, long before '
        'its 64 MiB', () {
      var produced = -1;
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry(
              'bomb.bin',
              const <int>[],
              compressedOverride: deflateBombBody(64 * 1024 * 1024),
              declaredUncompressedSize: 512,
              declaredCrc32: 0,
            ),
          ]),
        ),
        limits: roomy,
        unpackedBytesProbe: (n) => produced = n,
      );
      addTearDown(file.close);
      final watch = Stopwatch()..start();
      expect(
        () => file.writeTo(file.entries.single, '${folder.path}/out'),
        refusedWith("'bomb.bin' holds more than the 512 bytes it declares"),
      );
      expect(produced, inInclusiveRange(1, 512));
      expect(namesInFolder(), ['archive.zip']);
      // Unpacking all 64 MiB takes a good part of a second; stopping at
      // 512 bytes takes no time worth measuring. Generous bound.
      expect(watch.elapsedMilliseconds, lessThan(500));
    });

    test('the probe reports what was unpacked for each entry taken', () {
      final reported = <int>[];
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('words.txt', words),
            HostileEntry('noise.bin', noise, deflate: false),
          ]),
        ),
        limits: roomy,
        unpackedBytesProbe: reported.add,
      );
      addTearDown(file.close);
      file
        ..read(file.entry('words.txt')!, maxBytes: roomy.maxEntryBytes)
        ..writeTo(file.entry('noise.bin')!, '${folder.path}/out');
      expect(reported, [300000, 70000]);
    });
  });

  group('the entry header carries the name of the directory (rule N2)', () {
    test('another name, a longer one, a shorter one and an empty one are '
        'refused when the file is opened', () {
      for (final local in ['cover_b.jpg', 'cover_a.jpg.bak', 'cover_a', '']) {
        expect(
          () => BoundedZipFile.open(
            onDisk(
              buildHostileZip([
                HostileEntry('cover_a.jpg', [
                  1,
                  2,
                  3,
                ], localNameBytes: local.codeUnits),
              ]),
            ),
            limits: roomy,
          ),
          refusedWith('entry header and directory name the entry differently'),
          reason: "'$local'",
        );
      }
    });

    test('the same bytes are the same name, whatever they mean: a path, '
        'and bytes that are not UTF-8', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('dir/leaf.txt', [1]),
            HostileEntry('x', [2], nameBytes: [0x63, 0x61, 0x66, 0xE9]),
          ]),
        ),
        limits: roomy,
      );
      addTearDown(file.close);
      expect([for (final e in file.entries) e.name], ['leaf.txt', 'café']);
    });
  });

  group('a file that changes while it is open', () {
    test('cut after it was opened: taking an entry is refused, and a file '
        'being written is removed', () {
      final zip = buildHostileZip([
        HostileEntry('noise.bin', noise, deflate: false),
        HostileEntry('words.txt', words),
      ]);
      final path = onDisk(zip);
      final file = BoundedZipFile.open(path, limits: roomy);
      addTearDown(file.close);
      // Someone cuts the file in the middle of the first entry.
      File(path).writeAsBytesSync(Uint8List.sublistView(zip, 0, 30000));

      for (final name in ['noise.bin', 'words.txt']) {
        expect(
          () => file.read(file.entry(name)!, maxBytes: roomy.maxEntryBytes),
          refusedWith('changed while it was being read'),
          reason: name,
        );
        expect(
          () => file.writeTo(file.entry(name)!, '${folder.path}/out'),
          refusedWith('changed while it was being read'),
          reason: name,
        );
      }
      expect(namesInFolder(), ['archive.zip']);
    });

    test('content changed after it was opened, same length: the checksum '
        'refuses the entry', () {
      final zip = buildHostileZip([
        HostileEntry('noise.bin', noise, deflate: false),
      ]);
      final path = onDisk(zip);
      final file = BoundedZipFile.open(path, limits: roomy);
      addTearDown(file.close);
      File(path).writeAsBytesSync(Uint8List.fromList(zip)..[5000] ^= 0x01);
      expect(
        () => file.read(file.entries.single, maxBytes: roomy.maxEntryBytes),
        refusedWith('failed its checksum'),
      );
    });
  });

  group('entries with a rule: taken, left out, ignored', () {
    /// `data*` up to 1,000 bytes, or the archive is refused; `cover_*` up
    /// to 100 bytes, left out above; any other name ignored.
    ZipEntryRule policy(String leaf) {
      if (leaf.startsWith('data')) {
        return const ZipEntryRule.take(maxBytes: 1000);
      }
      if (leaf.startsWith('cover_')) {
        return const ZipEntryRule.take(
          maxBytes: 100,
          tooLarge: ZipTooLarge.leaveOut,
        );
      }
      return const ZipEntryRule.ignore();
    }

    final hundred = List<int>.generate(100, (i) => i);

    test('an entry that is left out or ignored is never unpacked: its '
        'content can be anything', () {
      final unpacked = <int>[];
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('data.json', [1, 2, 3]),
            HostileEntry('cover_ok', hundred),
            // Declares 101 bytes: left out. What it really holds is a bomb
            // with a wrong checksum, which nobody ever finds out.
            HostileEntry(
              'cover_big',
              const [],
              compressedOverride: deflateBombBody(8 * 1024 * 1024),
              declaredUncompressedSize: 101,
              declaredCrc32: 7,
            ),
            // Unknown: ignored. A stream cut off, a wrong checksum.
            HostileEntry(
              'future.bin',
              const [],
              compressedOverride: const [0x00, 5, 0],
              declaredUncompressedSize: 5000000,
              declaredCrc32: 7,
            ),
          ]),
        ),
        limits: roomy,
        policy: policy,
        unpackedBytesProbe: unpacked.add,
      );
      addTearDown(file.close);
      expect(
        [for (final e in file.entries) (e.name, e.verdict)],
        [
          ('data.json', ZipEntryVerdict.take),
          ('cover_ok', ZipEntryVerdict.take),
          ('cover_big', ZipEntryVerdict.leftOut),
          ('future.bin', ZipEntryVerdict.ignored),
        ],
      );
      // The sizes are what the archive declares, also for these two.
      expect(file.entry('cover_big')!.size, 101);
      expect(file.entry('future.bin')!.size, 5000000);

      // Taking one is a mistake in the calling code, not a bad file.
      for (final name in ['cover_big', 'future.bin']) {
        expect(
          () => file.read(file.entry(name)!, maxBytes: 1 << 30),
          throwsStateError,
          reason: name,
        );
        expect(
          () => file.writeTo(file.entry(name)!, '${folder.path}/out'),
          throwsStateError,
          reason: name,
        );
      }
      expect(namesInFolder(), ['archive.zip']);
      expect(unpacked, isEmpty);

      expect(file.read(file.entry('cover_ok')!, maxBytes: 100), hundred);
      expect(file.read(file.entry('data.json')!, maxBytes: 100), [1, 2, 3]);
      expect(unpacked, [100, 3]);
    });

    test('an entry whose rule says "refuse" refuses the archive above its '
        'cap, before anything is unpacked', () {
      var probeCalls = 0;
      expect(
        () => BoundedZipFile.open(
          onDisk(
            buildHostileZip([
              HostileEntry('cover_ok', hundred),
              HostileEntry('data.db', List<int>.filled(1001, 1)),
            ]),
          ),
          limits: roomy,
          policy: policy,
          unpackedBytesProbe: (_) => probeCalls++,
        ),
        refusedWith("'data.db' exceeds per-entry cap (1000 bytes)"),
      );
      expect(probeCalls, 0);
    });

    test('a cover that DECLARES a size under its cap and holds more is not '
        '"left out": the entry is refused when it is taken', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry(
              'cover_liar',
              List<int>.filled(5000, 1),
              declaredUncompressedSize: 100,
            ),
          ]),
        ),
        limits: roomy,
        policy: policy,
      );
      addTearDown(file.close);
      final entry = file.entries.single;
      expect(entry.verdict, ZipEntryVerdict.take);
      expect(
        () => file.read(entry, maxBytes: 100),
        refusedWith("'cover_liar' holds more than the 100 bytes it declares"),
      );
    });

    test('the header of an entry that will not be taken is checked like '
        'any other: a damaged one refuses the archive', () {
      // The second entry is unknown (ignored) and its header offset leads
      // nowhere.
      expect(
        () => BoundedZipFile.open(
          onDisk(
            buildHostileZip([
              HostileEntry('data.json', [1, 2, 3]),
              HostileEntry('future.bin', [9], localHeaderOffsetOverride: 7),
            ]),
          ),
          limits: roomy,
          policy: policy,
        ),
        refusedWith('entry header has a wrong signature'),
      );
      // And a cover that is left out, with another name in its header.
      expect(
        () => BoundedZipFile.open(
          onDisk(
            buildHostileZip([
              HostileEntry(
                'cover_big',
                List<int>.filled(101, 1),
                localNameBytes: 'cover_xxx'.codeUnits,
              ),
            ]),
          ),
          limits: roomy,
          policy: policy,
        ),
        refusedWith('entry header and directory name the entry differently'),
      );
    });

    test('the content total counts what is taken; the number of entries '
        'counts every entry', () {
      // 300 bytes may be unpacked. Three covers of 100 are taken; two
      // oversized covers and an unknown entry declare 600 more.
      HostileEntry big(String name) =>
          HostileEntry(name, List<int>.filled(200, 1), deflate: false);
      final entries = [
        HostileEntry('cover_1', hundred),
        big('cover_big_1'),
        HostileEntry('cover_2', hundred),
        big('cover_big_2'),
        HostileEntry('cover_3', hundred),
        big('unknown'),
      ];
      final tight = ZipLimits(
        maxEntryBytes: 300,
        maxTotalBytes: 300,
        maxEntries: 6,
        maxArchiveBytes: 1024 * 1024,
      );
      final file = BoundedZipFile.open(
        onDisk(buildHostileZip(entries)),
        limits: tight,
        policy: policy,
      );
      addTearDown(file.close);
      expect(
        [
          for (final e in file.entries)
            if (e.verdict == ZipEntryVerdict.take) e.name,
        ],
        ['cover_1', 'cover_2', 'cover_3'],
      );
      // One more entry, of any kind, is one too many.
      expect(
        () => BoundedZipFile.open(
          onDisk(
            buildHostileZip([...entries, big('unknown_2')]),
            name: 'b.zip',
          ),
          limits: tight,
          policy: policy,
        ),
        refusedWith('too many entries (>6)'),
      );
    });
  });

  group('using the reader wrongly is an error of the calling code', () {
    test('after `close` nothing can be taken; closing twice is fine', () {
      final file = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('a', [1]),
          ]),
        ),
        limits: roomy,
      );
      final entry = file.entries.single;
      file
        ..close()
        ..close();
      expect(() => file.read(entry, maxBytes: 10), throwsStateError);
      expect(() => file.writeTo(entry, '${folder.path}/out'), throwsStateError);
      expect(namesInFolder(), ['archive.zip']);
    });

    test('an entry of ANOTHER archive is refused, also when it has the '
        'same name', () {
      final first = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('a', [1]),
          ]),
          name: 'first.zip',
        ),
        limits: roomy,
      );
      final second = BoundedZipFile.open(
        onDisk(
          buildHostileZip([
            HostileEntry('other', [5, 5, 5, 5]),
            HostileEntry('a', [2, 2]),
          ]),
          name: 'second.zip',
        ),
        limits: roomy,
      );
      addTearDown(first.close);
      addTearDown(second.close);
      expect(
        () => first.read(second.entry('a')!, maxBytes: 10),
        throwsStateError,
      );
      expect(
        () => first.read(second.entry('other')!, maxBytes: 10),
        throwsStateError,
      );
      expect(first.read(first.entry('a')!, maxBytes: 10), [1]);
    });
  });

  test('the checksum the reader computes piece by piece is the one of the '
      'whole content', () {
    // 300,000 bytes arrive in several pieces from the sink, 70,000 in two
    // from the stored copy. A reader that restarted its checksum on a
    // piece would refuse these honest entries.
    expect(getCrc32(words), isNot(getCrc32(words.sublist(0, 65536))));
    final file = BoundedZipFile.open(
      onDisk(
        buildHostileZip([
          HostileEntry('words.txt', words),
          HostileEntry('noise.bin', noise, deflate: false),
        ]),
      ),
      limits: roomy,
    );
    addTearDown(file.close);
    expect(file.read(file.entries[0], maxBytes: 300000), words);
    expect(file.read(file.entries[1], maxBytes: 70000), noise);
  });
}
