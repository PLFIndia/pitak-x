import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

import 'hostile_zip_builder.dart';

/// The KIND of a refusal of the ZIP reader (`ZipRefusal`; backup rework
/// BR8).
///
/// WHY (beginner note): the Restore page tells "this file holds more than
/// a backup can" apart from "this file is damaged". It can only do that
/// when the reader says which of the two a refusal was. A refusal for size
/// or count names its kind; EVERYTHING else must stay `other`, which the
/// page reads as "do not trust this file". A kind that is wrong in that
/// direction would call a hostile file a merely large one, so both
/// directions are tested here.
///
/// The messages of the refusals are tested where the rules are
/// (`zip_entry_rules_test.dart`, `zip_reader_cases_test.dart`,
/// `bounded_zip_file_test.dart`); this file looks at the kind only.
void main() {
  late Directory folder;
  var files = 0;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('zip_refusal_kind_test');
  });
  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  /// Writes [zip] into the test's folder and gives its path.
  String onDisk(Uint8List zip) {
    final path = '${folder.path}/archive-${files++}.zip';
    File(path).writeAsBytesSync(zip);
    return path;
  }

  /// Four entries, 100 bytes each, 250 bytes in all.
  final limits = ZipLimits(
    maxEntryBytes: 100,
    maxTotalBytes: 250,
    maxEntries: 4,
  );

  /// An honest stored entry of [size] bytes.
  HostileEntry stored(String name, int size) =>
      HostileEntry(name, List<int>.filled(size, 7), deflate: false);

  /// The kind the reader refuses [zip] with when it OPENS it, or null when
  /// it takes the file.
  ZipRefusal? kindAtOpen(
    Uint8List zip, {
    ZipLimits? under,
    ZipEntryPolicy? policy,
  }) {
    try {
      BoundedZipFile.open(
        onDisk(zip),
        limits: under ?? limits,
        policy: policy,
      ).close();
      return null;
    } on BoundedExtractionException catch (e) {
      return e.kind;
    }
  }

  /// The kind [action] is refused with, or null when it is not refused.
  ZipRefusal? kindOf(void Function() action) {
    try {
      action();
      return null;
    } on BoundedExtractionException catch (e) {
      return e.kind;
    }
  }

  test('a refusal that names no kind is "other"', () {
    expect(const BoundedExtractionException('x').kind, ZipRefusal.other);
  });

  group('a refusal for size or count says which limit it was', () {
    test('the file itself is larger than allowed: fileTooLarge', () {
      final zip = buildHostileZip([stored('a', 10)]);
      ZipLimits withFileCap(int maxArchiveBytes) => ZipLimits(
        maxEntryBytes: 100,
        maxTotalBytes: 250,
        maxEntries: 4,
        maxArchiveBytes: maxArchiveBytes,
      );

      expect(kindAtOpen(zip, under: withFileCap(zip.length)), isNull);
      expect(
        kindAtOpen(zip, under: withFileCap(zip.length - 1)),
        ZipRefusal.fileTooLarge,
      );
    });

    // The reader counts entries in three places, because the count in the
    // end record is only a claim of the file. Each place is reached by a
    // file of its own here.
    group('more entries than allowed: tooManyEntries', () {
      test('where the end record claims too many', () {
        expect(
          kindAtOpen(buildHostileZip([stored('a', 1)], eocdEntryCount: 5)),
          ZipRefusal.tooManyEntries,
        );
      });

      test('where the end record claims few and the directory holds too '
          'many', () {
        expect(
          kindAtOpen(
            buildHostileZip([
              for (var i = 0; i < 5; i++) stored('e$i', 1),
            ], eocdEntryCount: 1),
          ),
          ZipRefusal.tooManyEntries,
        );
      });

      test('where the rules are handed too many records', () {
        final zip = buildHostileZip([
          for (var i = 0; i < 5; i++) stored('e$i', 1),
        ]);
        final records = ZipContainer.directory(
          zip,
          ZipContainer.locateEndRecord(zip),
        ).toList();
        expect(
          kindOf(() => checkZipEntries(records, limits: limits)),
          ZipRefusal.tooManyEntries,
        );
      });

      test('exactly as many as allowed are taken', () {
        expect(
          kindAtOpen(
            buildHostileZip([for (var i = 0; i < 4; i++) stored('e$i', 1)]),
          ),
          isNull,
        );
      });
    });

    group('one entry above its cap: entryTooLarge', () {
      test('without a rule per name, above the one cap for every entry', () {
        expect(kindAtOpen(buildHostileZip([stored('a', 100)])), isNull);
        expect(
          kindAtOpen(buildHostileZip([stored('a', 101)])),
          ZipRefusal.entryTooLarge,
        );
      });

      test('with a rule that refuses the archive above its cap', () {
        expect(
          kindAtOpen(
            buildHostileZip([stored('needed', 51)]),
            policy: (_) => const ZipEntryRule.take(maxBytes: 50),
          ),
          ZipRefusal.entryTooLarge,
        );
      });

      test('with a rule that leaves the entry out, nothing is refused', () {
        expect(
          kindAtOpen(
            buildHostileZip([stored('optional', 51)]),
            policy: (_) => const ZipEntryRule.take(
              maxBytes: 50,
              tooLarge: ZipTooLarge.leaveOut,
            ),
          ),
          isNull,
        );
      });
    });

    test('more content in total than allowed: contentTooLarge', () {
      // 100 + 100 + 50 = 250 fits; one byte more does not.
      expect(
        kindAtOpen(
          buildHostileZip([
            stored('a', 100),
            stored('b', 100),
            stored('c', 50),
          ]),
        ),
        isNull,
      );
      expect(
        kindAtOpen(
          buildHostileZip([
            stored('a', 100),
            stored('b', 100),
            stored('c', 51),
          ]),
        ),
        ZipRefusal.contentTooLarge,
      );
    });
  });

  group('every other refusal is "other": the file is not to be trusted', () {
    final one = [stored('a', 1)];

    test('what is wrong with the file as a whole', () {
      final zip = buildHostileZip(one);
      final cases = <String, ZipRefusal?>{
        'not a ZIP at all': kindAtOpen(
          Uint8List.fromList(List<int>.filled(200, 0x41)),
        ),
        'an empty file': kindAtOpen(Uint8List(0)),
        'zip64 in the end record': kindAtOpen(
          buildHostileZip(one, eocdEntryCount: 0xFFFF),
        ),
        'a directory larger than its cap': kindAtOpen(
          zip,
          under: ZipLimits(
            maxEntryBytes: 100,
            maxTotalBytes: 250,
            maxEntries: 4,
            maxCentralDirectoryBytes: 10,
          ),
        ),
        'a directory that lies outside the file': kindAtOpen(
          buildHostileZip(one, eocdCentralDirectoryOffset: 0x7FFFFFF0),
        ),
      };
      for (final entry in cases.entries) {
        expect(entry.value, ZipRefusal.other, reason: entry.key);
      }
    });

    test('what is wrong with one entry, found from what it declares', () {
      final cases = <String, ZipRefusal?>{
        'encrypted': kindAtOpen(
          buildHostileZip([
            HostileEntry('a', const [1], flags: 1),
          ]),
        ),
        'a method that is neither stored nor deflated': kindAtOpen(
          buildHostileZip([
            HostileEntry('a', const [1], method: 12),
          ]),
        ),
        'a folder': kindAtOpen(buildHostileZip([stored('dir/', 0)])),
        'an empty name': kindAtOpen(buildHostileZip([stored('', 1)])),
        'two entries with one name': kindAtOpen(
          buildHostileZip([stored('a', 1), stored('x/a', 1)]),
        ),
        'stored, with two different sizes': kindAtOpen(
          buildHostileZip([
            HostileEntry(
              'a',
              const [1, 2, 3],
              deflate: false,
              declaredUncompressedSize: 5,
            ),
          ]),
        ),
        'the two headers name the entry differently': kindAtOpen(
          buildHostileZip([
            HostileEntry('a', const [1], localNameBytes: 'b'.codeUnits),
          ]),
        ),
      };
      for (final entry in cases.entries) {
        expect(entry.value, ZipRefusal.other, reason: entry.key);
      }
    });

    test('what is found only when an entry is unpacked', () {
      BoundedZipFile opened(HostileEntry entry) {
        final file = BoundedZipFile.open(
          onDisk(buildHostileZip([entry])),
          limits: limits,
        );
        addTearDown(file.close);
        return file;
      }

      final badChecksum = opened(
        HostileEntry('a', const [1, 2, 3], declaredCrc32: 0),
      );
      expect(
        kindOf(
          () => badChecksum.read(badChecksum.entries.single, maxBytes: 100),
        ),
        ZipRefusal.other,
        reason: 'content that fails its checksum',
      );

      // Declares 10 bytes and unpacks to 4,000: within every limit as
      // DECLARED, so it is taken, and refused when it is unpacked.
      final bomb = opened(
        HostileEntry(
          'a',
          List<int>.filled(4000, 0),
          declaredUncompressedSize: 10,
        ),
      );
      expect(
        kindOf(() => bomb.read(bomb.entries.single, maxBytes: 100)),
        ZipRefusal.other,
        reason: 'more content than the entry declares',
      );
    });
  });
}
