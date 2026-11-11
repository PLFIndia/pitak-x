import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';

import 'hostile_zip_builder.dart';
import 'zip_reader_table.dart';

/// What the extractor does with ODD ZIP CONTAINERS: files that are not what
/// an honest writer produces, but that the reader has to give a verdict on.
///
/// WHY THIS FILE EXISTS (beginner note): in BR2 the app moved from `archive`
/// 3 to `archive` 4. The old extractor let the package read the ZIP's
/// directory and entry headers; the package's reader changed what it accepts
/// between the two versions. So before the move, every case below was run
/// against the RELEASED reader (1.9.7, `archive` 3.6.1) and its verdict
/// written down here. The extractor now reads the directory and the entry
/// headers itself (`zip_container.dart`), and these tests hold it to the
/// recorded verdicts.
///
/// Ten recorded verdicts changed on purpose, each to the STRICTER side (the
/// old reader accepted the file, the new one refuses it). They are marked
/// "stricter than 1.9.7" below, with the reason. No verdict changed the
/// other way.
///
/// The verdicts of the released reader were taken with a copy of the 1.9.7
/// extractor on `archive` 3.6.1, kept outside the repository; the list is
/// in `PLAN.md` ("BR2 result").
///
/// Since BR5 every case runs against every ZIP reader the app ships (see
/// `zip_reader_table.dart`).
void main() {
  for (final reader in zipReadersUnderTest) {
    group(reader.name, () => containerCases(reader));
  }
}

/// The recorded verdicts, asked of [reader].
void containerCases(ZipReaderUnderTest reader) {
  final roomy = ZipLimits(
    maxEntryBytes: 64 * 1024,
    maxTotalBytes: 256 * 1024,
    maxEntries: 16,
    maxArchiveBytes: 1024 * 1024,
  );

  Map<String, List<int>> accepted(Uint8List zip) => {
    for (final entry in reader.extract(zip, limits: roomy).entries)
      entry.key: entry.value,
  };

  void refused(Uint8List zip) => expect(
    () => reader.extract(zip, limits: roomy),
    throwsA(isA<BoundedExtractionException>()),
  );

  Uint8List u16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
  Uint8List u32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
  Uint8List u64(int value) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, value, Endian.little);

  /// One record of a ZIP "extra field": id, length, data.
  List<int> extra(int id, List<int> data) => [
    ...u16(id),
    ...u16(data.length),
    ...data,
  ];

  /// A complete end record (22 bytes) for use inside another record's
  /// comment.
  Uint8List endRecord({
    required int entries,
    required int directorySize,
    required int directoryOffset,
    required int commentLength,
  }) {
    final record = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, entries, Endian.little)
      ..setUint16(10, entries, Endian.little)
      ..setUint32(12, directorySize, Endian.little)
      ..setUint32(16, directoryOffset, Endian.little)
      ..setUint16(20, commentLength, Endian.little);
    return record.buffer.asUint8List();
  }

  // 300 bytes that deflate to fewer: an entry large enough to tell a correct
  // read from a shifted one.
  final data = List<int>.generate(300, (i) => (i * 7) % 251);
  final deflated = io.ZLibEncoder(raw: true).convert(data);

  // A one-entry archive is: local header (30) + name (1) + body, then one
  // directory record (46 + 1 = 47 bytes), then the end record (22).
  const oneRecord = 47;

  group('layout around the directory', () {
    test('bytes glued in front of the archive: no entry is found', () {
      // The offsets inside the file still count from the old start, so the
      // directory is not where the end record says. The reader does not
      // search for it: it finds no entry, and the caller then misses its
      // manifest. (`archive` 4 would search and find the entries.)
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
        HostileEntry('b', data),
      ], prefix: List<int>.filled(100, 0x20));
      expect(accepted(zip), isEmpty);
    });

    test('a gap between the directory and the end record is tolerated', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ], junkAfterDirectory: List<int>.filled(50, 0x41));
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });

    test('an empty archive has no entries', () {
      expect(accepted(buildHostileZip([])), isEmpty);
    });

    test('a directory that starts somewhere else yields no entry', () {
      // Offset 0 is the first local header, not a directory record.
      expect(
        accepted(
          buildHostileZip([
            HostileEntry('a', [1, 2, 3]),
          ], eocdCentralDirectoryOffset: 0),
        ),
        isEmpty,
      );
      expect(
        accepted(
          buildHostileZip(
            [
              HostileEntry('a', [1, 2, 3]),
            ],
            eocdCentralDirectoryOffset: 0,
            eocdCentralDirectorySize: 0,
          ),
        ),
        isEmpty,
      );
    });

    test('an end record that claims MORE entries than exist is tolerated', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1]),
        HostileEntry('b', [2]),
      ], eocdEntryCount: 5);
      expect(accepted(zip), {
        'a': [1],
        'b': [2],
      });
    });

    test('junk after the last record, inside the directory, ends the list', () {
      final zip = buildHostileZip(
        [
          HostileEntry('a', [1, 2, 3]),
        ],
        junkAfterDirectory: List<int>.filled(40, 0x41),
        eocdCentralDirectorySize: oneRecord + 40,
      );
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });

    test('fewer than four junk bytes inside the directory are refused', () {
      // Not enough bytes left to hold even a record signature.
      refused(
        buildHostileZip(
          [
            HostileEntry('a', [1, 2, 3]),
          ],
          junkAfterDirectory: [0x41, 0x42],
          eocdCentralDirectorySize: oneRecord + 2,
        ),
      );
    });

    test('a record cut off inside its fixed part is refused', () {
      refused(
        buildHostileZip([
          HostileEntry('a', [1, 2, 3]),
          HostileEntry('b', [4]),
        ], eocdCentralDirectorySize: oneRecord + 20),
      );
    });

    test('a record whose NAME is cut off is refused '
        '(stricter than 1.9.7)', () {
      // The directory ends three bytes into the second name. The released
      // reader quietly used those three bytes and accepted an entry called
      // "bbb". A record that does not fit inside the directory is damage.
      refused(
        buildHostileZip([
          HostileEntry('a', [1, 2, 3]),
          HostileEntry('bbbbbbbb', [4]),
        ], eocdCentralDirectorySize: oneRecord + 46 + 3),
      );
    });
  });

  group('the end record', () {
    test('a comment that holds a cut-off second end record is refused', () {
      final zip = buildHostileZip(
        [
          HostileEntry('a', [1, 2, 3]),
        ],
        eocdComment: [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0],
      );
      refused(zip);
    });

    test('a complete second end record at the very end is the one used', () {
      // It is the last valid record of the file. It names no entries.
      final zip = buildHostileZip(
        [
          HostileEntry('a', [1, 2, 3]),
        ],
        eocdComment: endRecord(
          entries: 0,
          directorySize: 0,
          directoryOffset: 0,
          commentLength: 0,
        ),
      );
      expect(accepted(zip), isEmpty);
    });

    test('a second end record with an overlong comment is refused '
        '(stricter than 1.9.7)', () {
      // The released reader accepted both files below. Its extractor
      // checked the FIRST record (one entry) and the package then read the
      // directory through the SECOND one, which the extractor's own search
      // had skipped because its comment does not fit. Even a second record
      // that claims 60,000 entries passed. Now a file with two end records
      // is refused: there is one record, and it gets every check.
      for (final claimed in [1, 60000]) {
        final probe = buildHostileZip([
          HostileEntry('a', [1, 2, 3]),
        ]);
        final zip = buildHostileZip(
          [
            HostileEntry('a', [1, 2, 3]),
          ],
          eocdComment: endRecord(
            entries: claimed,
            directorySize: oneRecord,
            directoryOffset: probe.length - 22 - oneRecord,
            commentLength: 5,
          ),
        );
        expect(
          () => reader.extract(zip, limits: roomy),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('more than one end-of-central-directory record'),
            ),
          ),
          reason: 'second record claims $claimed entries',
        );
      }
    });

    test('an end-record signature in the last four bytes is refused '
        '(stricter than 1.9.7)', () {
      // The released reader's package never looked at the last four bytes
      // of a file, so it used the real record and accepted this. One rule
      // for the whole comment is simpler than keeping that blind spot.
      refused(
        buildHostileZip(
          [
            HostileEntry('a', [1, 2, 3]),
          ],
          eocdComment: [0x41, 0x42, 0x50, 0x4b, 0x05, 0x06],
        ),
      );
    });

    test('other signatures inside a comment are fine', () {
      // The signature of an ENTRY header, and a lone "PK", are not the
      // signature of an end record.
      final zip = buildHostileZip(
        [
          HostileEntry('a', [1, 2, 3]),
        ],
        eocdComment: [0x50, 0x4b, 0x03, 0x04, 0x50, 0x4b, 0x41],
      );
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });
  });

  group('names', () {
    test('a Unicode-path extra field does not rename the entry', () {
      // (`archive` 4 would take the name from the extra field.)
      final zip = buildHostileZip([
        HostileEntry(
          'plain.txt',
          [1, 2, 3],
          centralExtra: extra(0x7075, [
            1,
            ...u32(0),
            ...utf8.encode('other.txt'),
          ]),
        ),
      ]);
      expect(accepted(zip).keys, ['plain.txt']);
    });

    test('the directory name wins over the name in the entry header', () {
      final zip = buildHostileZip([
        HostileEntry('central.txt', [
          1,
          2,
          3,
        ], localNameBytes: utf8.encode('local-name-longer.txt')),
      ]);
      expect(accepted(zip), {
        'central.txt': [1, 2, 3],
      });
    });

    test('a UTF-8 name is read as UTF-8, with or without the UTF-8 flag', () {
      expect(
        accepted(
          buildHostileZip([
            HostileEntry('पुस्तक.jpg', [1]),
          ]),
        ).keys,
        ['पुस्तक.jpg'],
      );
      expect(
        accepted(
          buildHostileZip([
            HostileEntry('é.jpg', [1], flags: 0x800),
          ]),
        ).keys,
        ['é.jpg'],
      );
    });

    test('a name that is not UTF-8 is read one byte per character', () {
      final zip = buildHostileZip([
        HostileEntry('x', [1], nameBytes: [0x63, 0x61, 0x66, 0xE9]),
      ]);
      expect(accepted(zip).keys, ['café']);
    });

    test('a backslash path is reduced to its leaf; a long name is kept', () {
      expect(
        accepted(
          buildHostileZip([
            HostileEntry(r'dir\leaf.txt', [1]),
          ]),
        ).keys,
        ['leaf.txt'],
      );
      final long = 'n' * 300;
      expect(
        accepted(
          buildHostileZip([
            HostileEntry(long, [1]),
          ]),
        ).keys,
        [long],
      );
    });

    test('a comment on a directory record is skipped', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3], centralComment: utf8.encode('hello')),
        HostileEntry('b', [4]),
      ]);
      expect(accepted(zip), {
        'a': [1, 2, 3],
        'b': [4],
      });
    });
  });

  group('extra fields of a directory record', () {
    test('well-formed extra fields are skipped', () {
      final zip = buildHostileZip([
        HostileEntry(
          'a',
          [1, 2, 3],
          centralExtra: [
            ...extra(0x5455, [1, 2, 3, 4, 5]),
            ...extra(0x7875, [1, 2, 3]),
          ],
        ),
      ]);
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });

    test('an extra field too short for one record header is refused', () {
      refused(
        buildHostileZip([
          HostileEntry('a', [1, 2, 3], centralExtra: [1, 2, 3]),
        ]),
      );
    });

    test('an unknown record that announces more than it holds ends the '
        'extra field', () {
      final zip = buildHostileZip([
        HostileEntry(
          'a',
          [1, 2, 3],
          centralExtra: [...u16(0x5455), ...u16(100), 1, 2],
        ),
      ]);
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });

    group('zip64 sizes on ONE entry (the end record itself may not be '
        'zip64)', () {
      test('a 64-bit size that fits is used', () {
        expect(
          accepted(
            buildHostileZip([
              HostileEntry(
                'a',
                data,
                declaredUncompressedSize: 0xFFFFFFFF,
                centralExtra: extra(1, u64(300)),
              ),
            ]),
          ),
          {'a': data},
        );
        expect(
          accepted(
            buildHostileZip([
              HostileEntry(
                'a',
                data,
                declaredCompressedSize: 0xFFFFFFFF,
                centralExtra: extra(1, u64(deflated.length)),
              ),
            ]),
          ),
          {'a': data},
        );
      });

      test('a 64-bit offset of the entry header is used', () {
        final zip = buildHostileZip([
          HostileEntry(
            'a',
            data,
            localHeaderOffsetOverride: 0xFFFFFFFF,
            centralExtra: extra(1, u64(0)),
          ),
        ]);
        expect(accepted(zip), {'a': data});
      });

      test('a 64-bit size over the cap is refused', () {
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredUncompressedSize: 0xFFFFFFFF,
              centralExtra: extra(1, u64(1 << 40)),
            ),
          ]),
        );
      });

      test('the marker without a usable 64-bit value is refused', () {
        // No zip64 record at all, or one too short to hold a size: the
        // size stays at the marker value (4 GiB), which is over the cap.
        refused(
          buildHostileZip([
            HostileEntry('a', data, declaredUncompressedSize: 0xFFFFFFFF),
          ]),
        );
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredUncompressedSize: 0xFFFFFFFF,
              centralExtra: extra(1, u32(300)),
            ),
          ]),
        );
      });

      test('a zip64 record that announces more than it holds is refused', () {
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredUncompressedSize: 0xFFFFFFFF,
              centralExtra: [...u16(1), ...u16(8), 1, 2],
            ),
          ]),
        );
      });

      test('a 64-bit value with the top bit set is refused '
          '(stricter than 1.9.7)', () {
        // Such a value reads as a NEGATIVE number in Dart. The released
        // reader accepted all three files: it took a negative compressed
        // size for "the rest of the file" and let a negative uncompressed
        // size pass the size check.
        final topBit = [0, 0, 0, 0, 0, 0, 0, 0x80];
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredCompressedSize: 0xFFFFFFFF,
              centralExtra: extra(1, topBit),
            ),
          ]),
        );
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredUncompressedSize: 0xFFFFFFFF,
              centralExtra: extra(1, topBit),
            ),
          ]),
        );
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              declaredCompressedSize: 0xFFFFFFFF,
              centralExtra: extra(1, List<int>.filled(8, 0xFF)),
            ),
          ]),
        );
      });

      test('a zip64 record is ignored when no field carries the marker', () {
        final zip = buildHostileZip([
          HostileEntry('a', data, centralExtra: extra(1, u64(1 << 40))),
        ]);
        expect(accepted(zip), {'a': data});
      });
    });
  });

  group('the entry header in front of the content', () {
    test('an extra field in the entry header is skipped', () {
      final zip = buildHostileZip([
        HostileEntry(
          'a',
          data,
          localExtra: extra(0x5455, List<int>.filled(16, 9)),
        ),
      ]);
      expect(accepted(zip), {'a': data});
    });

    test('entries written by a streaming writer (data descriptor) are '
        'read', () {
      // Java's ZipOutputStream writes zeros into the entry header and the
      // real sizes after the content. The directory has the truth.
      final zip = buildHostileZip([
        HostileEntry('a', data, dataDescriptor: true),
        HostileEntry('b', [4, 5, 6], dataDescriptor: true, deflate: false),
      ]);
      expect(accepted(zip), {
        'a': data,
        'b': [4, 5, 6],
      });
    });

    test('a wrong signature is refused', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]);
      zip[0] = 0x51;
      refused(zip);
    });

    test('an offset that does not lead to an entry header is refused', () {
      final probe = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]);
      for (final offset in [
        0x00FFFFFF, // far beyond the file
        probe.length - 22, // the end record
        probe.length - 10, // ten bytes before the end of the file
      ]) {
        refused(
          buildHostileZip([
            HostileEntry('a', [1, 2, 3], localHeaderOffsetOverride: offset),
          ]),
        );
      }
    });

    test('a name or extra length that points beyond the file is refused', () {
      final longName = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]);
      longName[26] = 0x60; // name length 60,000
      longName[27] = 0xEA;
      refused(longName);

      final longExtra = buildHostileZip([
        HostileEntry('a', [1, 2, 3], deflate: false),
      ]);
      longExtra[28] = 0x60; // extra length 60,000
      longExtra[29] = 0xEA;
      refused(longExtra);
    });

    test('two directory records may share one content', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
        HostileEntry('b', [1, 2, 3], localHeaderOffsetOverride: 0),
      ]);
      expect(accepted(zip), {
        'a': [1, 2, 3],
        'b': [1, 2, 3],
      });
    });

    test('the directory decides the method, not the entry header', () {
      final zip = buildHostileZip([HostileEntry('a', data)]);
      zip[8] = 0; // entry header says "stored"; the directory says deflate
      zip[9] = 0;
      expect(accepted(zip), {'a': data});
    });

    test('an entry header that says "encrypted" while the directory does '
        'not is refused (stricter than 1.9.7)', () {
      // The released reader looked at the directory's flag only and read
      // the content as plain. Two headers that disagree about encryption
      // are not the work of an honest writer.
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]);
      zip[6] |= 0x01;
      refused(zip);
    });

    test('an entry header that announces a data descriptor needs room for '
        'one', () {
      // Flag bit 3 without a descriptor: the reader takes the bytes that
      // follow the content for one. With honest sizes the directory
      // follows, so there is room.
      final honest = buildHostileZip([HostileEntry('a', data)]);
      honest[6] |= 0x08;
      expect(accepted(honest), {'a': data});

      // With a compressed size that points beyond the file there is none.
      final beyond = buildHostileZip([
        HostileEntry('a', data, declaredCompressedSize: 100000),
      ]);
      beyond[6] |= 0x08;
      refused(beyond);
    });
  });

  group('the content range', () {
    test('empty entries, stored and deflated', () {
      expect(
        accepted(
          buildHostileZip([HostileEntry('empty', const [], deflate: false)]),
        ),
        {'empty': <int>[]},
      );
      expect(accepted(buildHostileZip([HostileEntry('empty', const [])])), {
        'empty': <int>[],
      });
    });

    test('deflate: a compressed size that is too LARGE is tolerated when '
        'the stream ends by itself', () {
      // The deflate stream carries its own end mark. The checksum still has
      // to match.
      expect(
        accepted(
          buildHostileZip([
            // Runs into the directory.
            HostileEntry(
              'a',
              data,
              declaredCompressedSize: deflated.length + 30,
            ),
          ]),
        ),
        {'a': data},
      );
      expect(
        accepted(
          buildHostileZip([
            // Points beyond the end of the file.
            HostileEntry('a', data, declaredCompressedSize: 100000),
          ]),
        ),
        {'a': data},
      );
    });

    test('deflate: bytes after the end mark, inside the compressed size, '
        'are ignored', () {
      final zip = buildHostileZip([
        HostileEntry('a', data, compressedOverride: [...deflated, 1, 2, 3, 4]),
      ]);
      expect(accepted(zip), {'a': data});
    });

    test('deflate: a compressed size that is too SMALL fails the '
        'checksum', () {
      refused(
        buildHostileZip([
          HostileEntry('a', data, declaredCompressedSize: deflated.length - 20),
        ]),
      );
    });

    group('deflate: a stream that stops without its end mark', () {
      // One stored block that is NOT marked as the last one, then a block
      // header of a type no deflate stream may contain. The inflater stops
      // there and hands back the first block; the checksum is made to match
      // exactly that block.
      final first = [1, 2, 3, 4, 5];
      final stopsEarly = [0x00, 5, 0, 0xFA, 0xFF, ...first, 0x06];

      void refusedForMissingEnd(Uint8List zip) => expect(
        () => reader.extract(zip, limits: roomy),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('deflate stream has no end mark'),
          ),
        ),
      );

      test('is refused although the checksum matches '
          '(stricter than 1.9.7)', () {
        // The released reader accepted both files: its inflater returned
        // what it had and only the checksum was looked at.
        refusedForMissingEnd(
          buildHostileZip([
            HostileEntry('a', first, compressedOverride: stopsEarly),
          ]),
        );
        refusedForMissingEnd(
          buildHostileZip([
            HostileEntry(
              'a',
              first,
              compressedOverride: stopsEarly,
              declaredCompressedSize: 100000,
            ),
          ]),
        );
      });

      test('a real stream cut short is refused, with an honest size and '
          'with one beyond the file', () {
        final cut = deflated.sublist(0, deflated.length - 6);
        refused(
          buildHostileZip([HostileEntry('a', data, compressedOverride: cut)]),
        );
        refused(
          buildHostileZip([
            HostileEntry(
              'a',
              data,
              compressedOverride: cut,
              declaredCompressedSize: 100000,
            ),
          ]),
        );
      });

      test('an empty entry as the released writer stores it is read', () {
        // `archive` 3.6.1 wrote an entry without content as a deflate
        // stream of two bytes: one empty block, flagged "last". It has its
        // end mark.
        final zip = buildHostileZip([
          HostileEntry('cover_empty.jpg', const [], compressedOverride: [3, 0]),
        ]);
        expect(accepted(zip), {'cover_empty.jpg': <int>[]});
      });
    });

    test('deflate: repeated data that points in front of the output is '
        'refused, whatever the checksum says', () {
      // A hand-built block: "copy 3 bytes from 1 byte back" as the very
      // first instruction, when nothing has been written yet. `archive` 4
      // notices and stops quietly, with nothing written; the entry is then
      // refused for its missing end mark. (The released reader refused it
      // through a RangeError.)
      const badDistance = [0x03, 0x02, 0x00];
      for (final claim in [
        (crc: 0, size: 0), // "the entry is empty"
        (crc: getCrc32(const [0, 0, 0]), size: 3), // "three zero bytes"
      ]) {
        expect(
          () => reader.extract(
            buildHostileZip([
              HostileEntry(
                'a',
                const [],
                compressedOverride: badDistance,
                declaredCrc32: claim.crc,
                declaredUncompressedSize: claim.size,
              ),
            ]),
            limits: roomy,
          ),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('deflate stream has no end mark'),
            ),
          ),
        );
      }
    });

    test('stored: a size that points beyond the file is refused before the '
        'checksum is looked at', () {
      // The released reader refused this file too, but through the
      // checksum: it took the rest of the file as the content (read in its
      // source), so a checksum made to fit would have passed. A stored
      // entry has no end mark; a size beyond the file is refused outright.
      expect(
        () => reader.extract(
          buildHostileZip([
            HostileEntry(
              'a',
              [1, 2, 3],
              deflate: false,
              declaredCompressedSize: 5000,
              declaredUncompressedSize: 5000,
            ),
          ]),
          limits: roomy,
        ),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('stored data ends before its size'),
          ),
        ),
      );
    });

    test('deflate: a stream cut off in the middle fails the checksum', () {
      refused(
        buildHostileZip([
          HostileEntry(
            'a',
            const [],
            compressedOverride: deflated.sublist(0, 10),
            declaredCrc32: 0,
            declaredUncompressedSize: 0,
          ),
        ]),
      );
    });

    test('stored: a size that runs into the directory fails the checksum', () {
      refused(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            deflate: false,
            declaredCompressedSize: 10,
            declaredUncompressedSize: 10,
          ),
        ]),
      );
    });

    test('stored: the compressed size decides the length, not the declared '
        'uncompressed size', () {
      final zip = buildHostileZip([
        HostileEntry(
          'a',
          [1, 2, 3],
          deflate: false,
          declaredUncompressedSize: 9,
        ),
      ]);
      expect(accepted(zip), {
        'a': [1, 2, 3],
      });
    });
  });
}
