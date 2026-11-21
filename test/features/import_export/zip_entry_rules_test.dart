import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';

import 'hostile_zip_builder.dart';

/// The rules on what a ZIP directory DECLARES, alone: no file, nothing
/// unpacked (backup rework BR5).
///
/// WHY (beginner note): the reader that works from a file runs these rules
/// for every entry before it unpacks one byte. They decide whether a file
/// is refused, and for each entry whether it is taken, left out or
/// ignored. They are plain Dart, so the tests hand them directory records
/// and compare the answer. (A record can only be made by the container
/// reader, so each test builds a small archive and reads its directory.)
void main() {
  List<ZipDirectoryEntry> recordsOf(Uint8List zip) =>
      ZipContainer.directory(zip, ZipContainer.locateEndRecord(zip)).toList();

  final limits = ZipLimits(
    maxEntryBytes: 100,
    maxTotalBytes: 250,
    maxEntries: 4,
  );

  /// An honest stored entry of [size] bytes: both declared sizes are
  /// [size], and nothing has to be compressed to get an exact number.
  HostileEntry stored(String name, int size) =>
      HostileEntry(name, List<int>.filled(size, 7), deflate: false);

  Matcher refusedWith(String part) => throwsA(
    isA<BoundedExtractionException>().having(
      (e) => e.message,
      'message',
      contains(part),
    ),
  );

  List<(String, ZipEntryVerdict)> verdicts(List<CheckedZipEntry> checked) => [
    for (final entry in checked) (entry.leaf, entry.verdict),
  ];

  group('without a policy: one cap for every entry, as the in-memory '
      'reader has it', () {
    test('entries at the cap and at the total are taken, in order', () {
      final checked = checkZipEntries(
        recordsOf(
          buildHostileZip([
            stored('a', 100),
            stored('dir/b', 100),
            stored('c', 50),
          ]),
        ),
        limits: limits,
      );
      expect(verdicts(checked), [
        ('a', ZipEntryVerdict.take),
        ('b', ZipEntryVerdict.take),
        ('c', ZipEntryVerdict.take),
      ]);
      expect(checked[1].record.uncompressedSize, 100);
    });

    test('one byte over the cap refuses the archive', () {
      expect(
        () => checkZipEntries(
          recordsOf(buildHostileZip([stored('a', 101)])),
          limits: limits,
        ),
        refusedWith("'a' exceeds per-entry cap (100 bytes)"),
      );
    });

    test('one byte over the total refuses the archive', () {
      expect(
        () => checkZipEntries(
          recordsOf(
            buildHostileZip([
              stored('a', 100),
              stored('b', 100),
              stored('c', 51),
            ]),
          ),
          limits: limits,
        ),
        refusedWith('Archive total exceeds cap (250 bytes)'),
      );
    });

    test('more records than entries are allowed refuse the archive', () {
      expect(
        () => checkZipEntries(
          recordsOf(
            buildHostileZip([for (var i = 0; i < 5; i++) stored('e$i', 1)]),
          ),
          limits: limits,
        ),
        refusedWith('too many entries (>4)'),
      );
    });

    test('an empty directory gives an empty list', () {
      expect(
        checkZipEntries(recordsOf(buildHostileZip([])), limits: limits),
        isEmpty,
      );
    });
  });

  group('rules that hold for every entry, whatever its rule', () {
    // Each archive is checked under three policies. An entry that would be
    // ignored or left out is refused like one that is taken: these rules
    // are about the archive, not about what the caller wants from it.
    final policies = <String, ZipEntryPolicy?>{
      'no policy': null,
      'ignore everything': (_) => const ZipEntryRule.ignore(),
      'leave out everything above 0 bytes': (_) =>
          const ZipEntryRule.take(maxBytes: 0, tooLarge: ZipTooLarge.leaveOut),
    };

    void refusedUnderEveryPolicy(Uint8List zip, String part) {
      for (final MapEntry(key: name, value: policy) in policies.entries) {
        expect(
          () => checkZipEntries(recordsOf(zip), limits: limits, policy: policy),
          refusedWith(part),
          reason: name,
        );
      }
    }

    test('the name rules: a folder, an empty name, NUL, a name twice', () {
      refusedUnderEveryPolicy(
        buildHostileZip([HostileEntry('covers/', const [], deflate: false)]),
        'directory entry',
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry('', [1]),
        ]),
        'empty filename',
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry('a\u0000b', [1]),
        ]),
        'unsafe filename',
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry('x/n', [1]),
          HostileEntry(r'y\n', [2]),
        ]),
        "duplicate entry name: 'n'",
      );
    });

    test('an encrypted entry and an unknown method', () {
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry('a', [1], flags: 0x1),
        ]),
        "'a' is encrypted",
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry('a', [1], method: 93),
        ]),
        'unsupported compression method 93',
      );
    });

    test('N1: a stored entry that declares two different sizes', () {
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            deflate: false,
            declaredUncompressedSize: 9,
          ),
        ]),
        "'a' is stored, but declares two different sizes",
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            deflate: false,
            declaredCompressedSize: 2,
          ),
        ]),
        "'a' is stored, but declares two different sizes",
      );
      // A DEFLATED entry has two different sizes by nature.
      expect(
        verdicts(
          checkZipEntries(
            recordsOf(
              buildHostileZip([HostileEntry('a', List<int>.filled(90, 1))]),
            ),
            limits: limits,
          ),
        ),
        [('a', ZipEntryVerdict.take)],
      );
    });

    test('N3: a size, an offset or a disk number with the zip64 marker', () {
      List<int> zip64(List<int> value) => [1, 0, value.length, 0, ...value];
      final eight = List<int>.filled(8, 0)..[0] = 3;

      // Each of the three 32-bit fields, with a zip64 record that would
      // give a small, harmless value.
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            declaredUncompressedSize: 0xFFFFFFFF,
            centralExtra: zip64(eight),
          ),
        ]),
        "'a' uses zip64",
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            deflate: false,
            declaredCompressedSize: 0xFFFFFFFF,
            centralExtra: zip64(eight),
          ),
        ]),
        "'a' uses zip64",
      );
      refusedUnderEveryPolicy(
        buildHostileZip([
          HostileEntry(
            'a',
            [1, 2, 3],
            localHeaderOffsetOverride: 0xFFFFFFFF,
            centralExtra: zip64(List<int>.filled(8, 0)),
          ),
        ]),
        "'a' uses zip64",
      );

      // The disk number: the builder has no option for it, so the two
      // bytes are set by hand (offset 34 of the directory record).
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3], centralExtra: zip64([0, 0, 0, 0])),
      ]);
      final directoryAt = ZipContainer.locateEndRecord(
        zip,
      ).centralDirectoryOffset;
      zip[directoryAt + 34] = 0xFF;
      zip[directoryAt + 35] = 0xFF;
      refusedUnderEveryPolicy(zip, "'a' uses zip64");
    });

    test('a zip64 record that no field points to changes nothing', () {
      final zip = buildHostileZip([
        HostileEntry(
          'a',
          [1, 2, 3],
          deflate: false,
          centralExtra: [1, 0, 8, 0, 0, 0, 0, 0, 0, 1, 0, 0],
        ),
      ]);
      final record = recordsOf(zip).single;
      expect(record.hasZip64Marker, isFalse);
      expect(verdicts(checkZipEntries([record], limits: limits)), [
        ('a', ZipEntryVerdict.take),
      ]);
    });
  });

  group('with a policy: a rule per entry name', () {
    /// Covers may be 10 bytes and are left out above that; `data` may be 60
    /// and refuses the archive above that; anything else is ignored.
    ZipEntryRule policy(String leaf) {
      if (leaf.startsWith('cover_')) {
        return const ZipEntryRule.take(
          maxBytes: 10,
          tooLarge: ZipTooLarge.leaveOut,
        );
      }
      if (leaf == 'data') return const ZipEntryRule.take(maxBytes: 60);
      return const ZipEntryRule.ignore();
    }

    test('take, left out and ignored, each from its rule', () {
      final checked = checkZipEntries(
        recordsOf(
          buildHostileZip([
            stored('data', 60),
            stored('cover_at_cap', 10),
            stored('cover_over', 11),
            stored('notes.txt', 5),
          ]),
        ),
        limits: limits,
        policy: policy,
      );
      expect(verdicts(checked), [
        ('data', ZipEntryVerdict.take),
        ('cover_at_cap', ZipEntryVerdict.take),
        ('cover_over', ZipEntryVerdict.leftOut),
        ('notes.txt', ZipEntryVerdict.ignored),
      ]);
    });

    test('above its cap, an entry whose rule says "refuse" refuses the '
        'archive', () {
      expect(
        () => checkZipEntries(
          recordsOf(buildHostileZip([stored('data', 61)])),
          limits: limits,
          policy: policy,
        ),
        refusedWith("'data' exceeds per-entry cap (60 bytes)"),
      );
    });

    test('the cap of a rule may be ABOVE the one cap of the limits, and '
        'below it', () {
      // The limits' one cap (100) is only the rule of an archive without a
      // policy. With a policy, each name has its own number.
      ZipEntryRule roomy(String leaf) => const ZipEntryRule.take(maxBytes: 200);
      expect(
        verdicts(
          checkZipEntries(
            recordsOf(buildHostileZip([stored('big', 150)])),
            limits: limits,
            policy: roomy,
          ),
        ),
        [('big', ZipEntryVerdict.take)],
      );
    });

    test('the content total counts what is TAKEN: entries left out or '
        'ignored add nothing', () {
      // 60 + 10 are taken (70 of the 80 allowed here). The entries left
      // out and ignored declare 160 more and do not count. The rules use
      // the record only, so their content is never touched: each
      // "declares" 80 bytes and holds one.
      HostileEntry declares80(String name) => HostileEntry(
        name,
        [1],
        deflate: false,
        declaredUncompressedSize: 80,
        declaredCompressedSize: 80,
      );
      final checked = checkZipEntries(
        recordsOf(
          buildHostileZip([
            stored('data', 60),
            declares80('cover_big'),
            stored('cover_a', 10),
            declares80('unknown'),
          ]),
        ),
        limits: ZipLimits(maxEntryBytes: 80, maxTotalBytes: 80, maxEntries: 4),
        policy: policy,
      );
      expect(verdicts(checked), [
        ('data', ZipEntryVerdict.take),
        ('cover_big', ZipEntryVerdict.leftOut),
        ('cover_a', ZipEntryVerdict.take),
        ('unknown', ZipEntryVerdict.ignored),
      ]);
      // One taken byte more is over the total of 80.
      expect(
        () => checkZipEntries(
          recordsOf(
            buildHostileZip([
              stored('data', 60),
              stored('cover_a', 10),
              stored('cover_b', 10),
              stored('cover_c', 1),
            ]),
          ),
          limits: ZipLimits(
            maxEntryBytes: 80,
            maxTotalBytes: 80,
            maxEntries: 4,
          ),
          policy: policy,
        ),
        refusedWith('Archive total exceeds cap (80 bytes)'),
      );
    });

    test('the number of entries counts EVERY entry, also ignored ones', () {
      expect(
        () => checkZipEntries(
          recordsOf(
            buildHostileZip([
              for (var i = 0; i < 5; i++) stored('unknown_$i', 1),
            ]),
          ),
          limits: limits,
          policy: policy,
        ),
        refusedWith('too many entries (>4)'),
      );
    });

    test('an ignored entry still takes its name: a second entry of that '
        'name is refused', () {
      expect(
        () => checkZipEntries(
          recordsOf(
            buildHostileZip([stored('notes.txt', 1), stored('notes.txt', 2)]),
          ),
          limits: limits,
          policy: policy,
        ),
        refusedWith("duplicate entry name: 'notes.txt'"),
      );
    });

    test('the policy is asked for the LEAF, after the name rules', () {
      final asked = <String>[];
      checkZipEntries(
        recordsOf(
          buildHostileZip([
            stored('some/folder/cover_a', 1),
            stored(r'other\data', 1),
          ]),
        ),
        limits: limits,
        policy: (leaf) {
          asked.add(leaf);
          return policy(leaf);
        },
      );
      expect(asked, ['cover_a', 'data']);
    });
  });

  group('ZipEntryRule', () {
    test('a rule to take says its cap and what happens above it; the '
        'default above the cap is to refuse', () {
      const plain = ZipEntryRule.take(maxBytes: 5);
      expect(plain.maxBytes, 5);
      expect(plain.ignores, isFalse);
      expect(plain.tooLarge, ZipTooLarge.refuseArchive);
      const lenient = ZipEntryRule.take(
        maxBytes: 0,
        tooLarge: ZipTooLarge.leaveOut,
      );
      expect(lenient.maxBytes, 0);
      expect(lenient.tooLarge, ZipTooLarge.leaveOut);
    });

    test('a rule to ignore has no cap', () {
      const rule = ZipEntryRule.ignore();
      expect(rule.ignores, isTrue);
      expect(rule.maxBytes, isNull);
    });

    test('a negative cap is a mistake in the calling code', () {
      expect(
        () => ZipEntryRule.take(maxBytes: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('checkZipEndRecord', () {
    ZipEndRecord endOf(Uint8List zip) => ZipContainer.locateEndRecord(zip);
    final one = [stored('a', 3)];

    test('an honest end record passes, also exactly at the two caps', () {
      final zip = buildHostileZip([stored('a', 1), stored('b', 1)]);
      final end = endOf(zip);
      checkZipEndRecord(
        end,
        ZipLimits(
          maxEntryBytes: 10,
          maxTotalBytes: 10,
          maxEntries: 2,
          maxCentralDirectoryBytes: end.centralDirectorySize,
        ),
      );
    });

    test('zip64 in any of its three fields is refused', () {
      for (final zip in [
        buildHostileZip(one, eocdEntryCount: 0xFFFF),
        buildHostileZip(one, eocdCentralDirectorySize: 0xFFFFFFFF),
        buildHostileZip(one, eocdCentralDirectoryOffset: 0xFFFFFFFF),
      ]) {
        expect(
          () => checkZipEndRecord(endOf(zip), limits),
          refusedWith('Archive uses zip64'),
        );
      }
    });

    test('a count over the cap, and a directory over its cap', () {
      expect(
        () => checkZipEndRecord(
          endOf(buildHostileZip(one, eocdEntryCount: 5)),
          limits,
        ),
        refusedWith('too many entries (>4)'),
      );
      final zip = buildHostileZip(one);
      final size = endOf(zip).centralDirectorySize;
      expect(
        () => checkZipEndRecord(
          endOf(zip),
          ZipLimits(
            maxEntryBytes: 10,
            maxTotalBytes: 10,
            maxEntries: 4,
            maxCentralDirectoryBytes: size - 1,
          ),
        ),
        refusedWith('central directory is too large'),
      );
    });

    test('a directory that would reach into the end record, or lies '
        'beyond the file', () {
      final zip = buildHostileZip(one);
      final honest = endOf(zip);
      expect(
        () => checkZipEndRecord(
          endOf(
            buildHostileZip(
              one,
              eocdCentralDirectorySize: honest.centralDirectorySize + 1,
            ),
          ),
          limits,
        ),
        refusedWith('central directory lies outside the file'),
      );
      expect(
        () => checkZipEndRecord(
          endOf(buildHostileZip(one, eocdCentralDirectoryOffset: 0x7FFFFFF0)),
          limits,
        ),
        refusedWith('central directory lies outside the file'),
      );
    });
  });
}
