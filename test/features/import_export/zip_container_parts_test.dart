import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';

import 'hostile_zip_builder.dart';

/// `ZipContainer` on PARTS of a file must say what it says on the whole
/// file (backup rework BR5).
///
/// WHY (beginner note): the reader that works from a file on disk does not
/// load the file. It reads the last bytes (for the end record), the
/// directory, and 30 bytes per entry, and hands those parts to the same
/// `ZipContainer` the in-memory reader uses. These tests take archives of
/// many shapes, honest and odd, and compare the answers both ways.
void main() {
  /// Everything `ZipContainer` knows about a record, as plain values.
  List<Object?> fieldsOf(ZipDirectoryEntry entry) => [
    entry.name,
    entry.versionMadeBy,
    entry.flags,
    entry.method,
    entry.crc32,
    entry.compressedSize,
    entry.uncompressedSize,
    entry.externalAttributes,
    entry.localHeaderOffset,
  ];

  /// The answer or the reason for a refusal, so that two runs can be
  /// compared whether they succeed or not.
  Object? outcome(Object? Function() run) {
    try {
      return run();
    } on ZipContainerException catch (e) {
      return 'refused: ${e.message}';
    }
  }

  /// The last bytes of [zip] that can hold the end record, and where they
  /// start.
  ({Uint8List bytes, int offset}) tailOf(Uint8List zip) {
    final offset = zip.length > ZipContainer.endRecordSearchLength
        ? zip.length - ZipContainer.endRecordSearchLength
        : 0;
    return (bytes: Uint8List.sublistView(zip, offset), offset: offset);
  }

  final data = List<int>.generate(300, (i) => (i * 7) % 251);
  final large = List<int>.generate(100000, (i) => (i * 13) % 253);

  final archives = <String, Uint8List>{
    'empty': buildHostileZip([]),
    'two small entries': buildHostileZip([
      HostileEntry('a', [1, 2, 3]),
      HostileEntry('b', data),
    ]),
    'longer than the search length': buildHostileZip([
      HostileEntry('big', large, deflate: false),
      HostileEntry('b', data),
    ]),
    'a comment behind the end record': buildHostileZip([
      HostileEntry('a', data),
    ], eocdComment: List<int>.filled(300, 0x41)),
    'the longest comment, behind a large entry': buildHostileZip([
      HostileEntry('big', large, deflate: false),
    ], eocdComment: List<int>.filled(0xFFFF, 0x41)),
    'junk between the directory and the end record': buildHostileZip([
      HostileEntry('a', data),
    ], junkAfterDirectory: List<int>.filled(50, 0x41)),
    'bytes glued in front': buildHostileZip([
      HostileEntry('a', data),
    ], prefix: List<int>.filled(100, 0x20)),
    'sizes behind the data': buildHostileZip([
      HostileEntry('a', data, dataDescriptor: true),
      HostileEntry('b', [4, 5, 6], dataDescriptor: true, deflate: false),
    ]),
    'extra fields and a record comment': buildHostileZip([
      HostileEntry(
        'a',
        data,
        centralExtra: [0x55, 0x54, 5, 0, 1, 2, 3, 4, 5],
        localExtra: [0x55, 0x54, 2, 0, 9, 9],
        centralComment: [0x68, 0x69],
      ),
    ]),
    'a compressed size beyond the file': buildHostileZip([
      HostileEntry('a', data, declaredCompressedSize: 100000),
    ]),
    'an entry header far outside the file': buildHostileZip([
      HostileEntry('a', data, localHeaderOffsetOverride: 0x00FFFFFF),
    ]),
    'a second end record in the comment': buildHostileZip(
      [HostileEntry('a', data)],
      eocdComment: [0x41, 0x42, 0x50, 0x4b, 0x05, 0x06],
    ),
    'a directory record cut off': buildHostileZip([
      HostileEntry('a', [1, 2, 3]),
      HostileEntry('bbbbbbbb', [4]),
    ], eocdCentralDirectorySize: 47 + 46 + 3),
    'no end record within the search length': Uint8List.fromList([
      ...buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]),
      ...List<int>.filled(70 * 1024, 0),
    ]),
    'too short for an end record': Uint8List.fromList([1, 2, 3]),
  };

  for (final MapEntry(key: name, value: zip) in archives.entries) {
    test('$name: the end record from the last bytes is the one from the '
        'whole file', () {
      List<int> numbers(ZipEndRecord end) => [
        end.recordOffset,
        end.entryCount,
        end.centralDirectorySize,
        end.centralDirectoryOffset,
      ];
      final tail = tailOf(zip);
      expect(
        outcome(
          () => numbers(
            ZipContainer.locateEndRecord(tail.bytes, offsetInFile: tail.offset),
          ),
        ),
        outcome(() => numbers(ZipContainer.locateEndRecord(zip))),
      );
    });

    test('$name: the directory read as a block is the one read from the '
        'whole file', () {
      final ZipEndRecord end;
      try {
        end = ZipContainer.locateEndRecord(zip);
      } on ZipContainerException {
        return; // no end record: nothing to compare (the test above did)
      }
      // The extractor checks this before it reads the directory; an end
      // record that fails it never reaches `directory`.
      final start = end.centralDirectoryOffset;
      final stop = start + end.centralDirectorySize;
      if (stop > end.recordOffset) return;
      final block = Uint8List.sublistView(zip, start, stop);
      expect(
        outcome(
          () => ZipContainer.directory(
            block,
            end,
            offsetInFile: start,
          ).map(fieldsOf).toList(),
        ),
        outcome(() => ZipContainer.directory(zip, end).map(fieldsOf).toList()),
      );
    });

    test('$name: the content range in numbers is the view into the whole '
        'file', () {
      final List<ZipDirectoryEntry> entries;
      try {
        entries = ZipContainer.directory(
          zip,
          ZipContainer.locateEndRecord(zip),
        ).toList();
      } on ZipContainerException {
        return; // no readable directory: nothing to compare
      }
      for (final entry in entries) {
        final asked = <({int offset, int length})>[];
        final range = outcome(
          () => ZipContainer.contentRange(
            entry,
            fileLength: zip.length,
            read: (offset, length) {
              asked.add((offset: offset, length: length));
              return Uint8List.sublistView(zip, offset, offset + length);
            },
          ),
        );
        final view = outcome(() {
          final body = ZipContainer.body(zip, entry);
          return (
            start: body.bytes.offsetInBytes - zip.offsetInBytes,
            length: body.bytes.length,
            complete: body.complete,
          );
        });
        expect(range, view, reason: entry.name);
        // It never asks for bytes outside the file, and never for more
        // than an entry header (30) or the start of a descriptor (4).
        for (final read in asked) {
          expect(read.offset, greaterThanOrEqualTo(0), reason: entry.name);
          expect(
            read.offset + read.length,
            lessThanOrEqualTo(zip.length),
            reason: entry.name,
          );
          expect(read.length, anyOf(30, 4), reason: entry.name);
        }
      }
    });
  }

  test('the cases cover what they are meant to cover', () {
    // A guard for the table above: if a builder option changed its meaning,
    // these would no longer be the cases their names say.
    expect(
      archives['longer than the search length']!.length,
      greaterThan(ZipContainer.endRecordSearchLength),
    );
    expect(ZipContainer.endRecordSearchLength, 22 + 0xFFFF);
    expect(
      () => ZipContainer.locateEndRecord(
        archives['no end record within the search length']!,
      ),
      throwsA(isA<ZipContainerException>()),
    );
    final beyond = archives['a compressed size beyond the file']!;
    final entry = ZipContainer.directory(
      beyond,
      ZipContainer.locateEndRecord(beyond),
    ).single;
    expect(ZipContainer.body(beyond, entry).complete, isFalse);
  });
}
