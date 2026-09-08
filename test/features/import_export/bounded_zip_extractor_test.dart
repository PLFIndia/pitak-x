import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';

import 'hostile_zip_builder.dart';

void main() {
  m05Regressions();

  Uint8List zipOf(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  group('hasZipLocalFileHeader', () {
    test('recognises the PK local-file-header magic', () {
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x03, 0x04]), isTrue);
      expect(
        hasZipLocalFileHeader(
          zipOf({
            'a.txt': [1],
          }),
        ),
        isTrue,
      );
    });

    test('rejects text, short, and non-ZIP bytes', () {
      expect(hasZipLocalFileHeader('{"a":1}'.codeUnits), isFalse);
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x03]), isFalse);
      expect(hasZipLocalFileHeader(const <int>[]), isFalse);
      expect(hasZipLocalFileHeader([0x50, 0x4B, 0x05, 0x06]), isFalse);
    });
  });

  group('BoundedZipExtractor', () {
    test('extracts a flat zip into leaf→bytes', () {
      final zip = zipOf({
        'library.json': '{"a":1}'.codeUnits,
        'cover_x.jpg': [1, 2, 3],
      });
      final out = BoundedZipExtractor.extract(zip);
      expect(out.keys, containsAll(['library.json', 'cover_x.jpg']));
      expect(out['cover_x.jpg'], [1, 2, 3]);
    });

    test('strips directory components to the leaf (zip-slip defence)', () {
      final zip = zipOf({'sub/dir/library.json': '{}'.codeUnits});
      final out = BoundedZipExtractor.extract(zip);
      // The nested path reduces to its leaf and is accepted as a flat entry.
      expect(out.keys.single, 'library.json');
    });

    test('rejects too many entries', () {
      final limits = ZipLimits(
        maxEntryBytes: 1024,
        maxTotalBytes: 1024,
        maxEntries: 2,
      );
      final zip = zipOf({
        'a': [1],
        'b': [2],
        'c': [3],
      });
      expect(
        () => BoundedZipExtractor.extract(zip, limits: limits),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('rejects an entry over the per-entry cap', () {
      final limits = ZipLimits(
        maxEntryBytes: 4,
        maxTotalBytes: 1024,
        maxEntries: 16,
      );
      final zip = zipOf({'big': List<int>.filled(100, 7)});
      expect(
        () => BoundedZipExtractor.extract(zip, limits: limits),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('rejects when total exceeds the total cap', () {
      final limits = ZipLimits(
        maxEntryBytes: 10,
        maxTotalBytes: 12,
        maxEntries: 16,
      );
      final zip = zipOf({
        'a': List<int>.filled(8, 1),
        'b': List<int>.filled(8, 2),
      });
      expect(
        () => BoundedZipExtractor.extract(zip, limits: limits),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('rejects a non-zip payload cleanly', () {
      expect(
        () => BoundedZipExtractor.extract(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    // Regression (review 2026-09-03, Blocker): a TRUNCATED or BIT-FLIPPED
    // archive made the `archive` package throw `RangeError` — an Error, not
    // an Exception — which sailed past the old `on Exception` guard and
    // crashed restore/import on a merely corrupt file. Every corruption of a
    // valid archive must now surface as ONE typed failure (or decode fine).
    test('every truncation of a valid zip fails typed, never crashes', () {
      final good = zipOf({
        'manifest.json': List<int>.generate(64, (i) => i),
        'books.db': List<int>.generate(300, (i) => i % 251),
      });
      for (var cut = good.length - 1; cut > 4; cut -= 3) {
        final truncated = good.sublist(0, cut);
        try {
          BoundedZipExtractor.extract(truncated);
        } on BoundedExtractionException {
          // expected
        }
        // Any other throw type propagates out of the try and fails the test.
      }
    });

    test('every single-byte corruption fails typed, never crashes', () {
      final good = zipOf({
        'manifest.json': List<int>.generate(64, (i) => i),
        'books.db': List<int>.generate(300, (i) => i % 251),
      });
      for (var i = 0; i < good.length; i += 2) {
        final flipped = Uint8List.fromList(good)..[i] ^= 0xFF;
        try {
          BoundedZipExtractor.extract(flipped);
        } on BoundedExtractionException {
          // expected
        }
      }
    });

    test('rejects an entry whose header lies about its size (small)', () {
      // Declared size 1 byte, real content 64 bytes: the header check passes,
      // the ACTUAL-length check must still enforce the cap.
      final archive = Archive()
        ..addFile(ArchiveFile('x.bin', 1, List<int>.generate(64, (i) => i)));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(
        () => BoundedZipExtractor.extract(
          bytes,
          limits: ZipLimits(
            maxEntries: 10,
            maxEntryBytes: 32,
            maxTotalBytes: 1000,
          ),
        ),
        throwsA(isA<BoundedExtractionException>()),
      );
    });
  });
}

/// M05 regressions (astra-review.md): every limit must fire BEFORE the
/// dangerous allocation, and lying metadata must never be trusted.
///
/// Archives here are built by `hostile_zip_builder.dart` because the package
/// encoder cannot write dishonest headers. `limits` are tiny on purpose so
/// the tests run in milliseconds and a regression shows up as a real
/// allocation, not a timeout.
void m05Regressions() {
  final tiny = ZipLimits(
    maxEntryBytes: 1024,
    maxTotalBytes: 2048,
    maxEntries: 4,
  );

  group('M05 — compressed input cap', () {
    test('rejects an archive larger than maxArchiveBytes before decoding', () {
      // 3 KiB of stored zeros — well under the content caps, but over the
      // input cap we set. Must fail on LENGTH alone, never parse.
      final zip = buildHostileZip([
        HostileEntry('a.bin', List<int>.filled(3000, 0), deflate: false),
      ]);
      final limits = ZipLimits(
        maxEntryBytes: 4096,
        maxTotalBytes: 4096,
        maxEntries: 4,
        maxArchiveBytes: zip.length - 1,
      );
      expect(
        () => BoundedZipExtractor.extract(zip, limits: limits),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
      // Exactly at the cap is fine — the cap is inclusive.
      final ok = ZipLimits(
        maxEntryBytes: 4096,
        maxTotalBytes: 4096,
        maxEntries: 4,
        maxArchiveBytes: zip.length,
      );
      expect(
        BoundedZipExtractor.extract(zip, limits: ok)['a.bin']!.length,
        3000,
      );
    });

    test('default input cap follows the total cap plus header slack', () {
      final d = ZipLimits.pitakaBackup;
      expect(d.maxArchiveBytes, greaterThan(d.maxTotalBytes));
      expect(d.maxCentralDirectoryBytes, greaterThan(0));
      for (final bad in [0, -1]) {
        expect(
          () => ZipLimits(
            maxEntryBytes: 10,
            maxTotalBytes: 10,
            maxEntries: 1,
            maxArchiveBytes: bad,
          ),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => ZipLimits(
            maxEntryBytes: 10,
            maxTotalBytes: 10,
            maxEntries: 1,
            maxCentralDirectoryBytes: bad,
          ),
          throwsA(isA<AssertionError>()),
        );
      }
    });
  });

  group('M05 — end-of-central-directory pre-checks (before ZipDecoder)', () {
    test('rejects a declared entry count over maxEntries', () {
      // 0xFFFE, not 0xFFFF: the latter is the zip64 marker (tested below).
      final zip = buildHostileZip([
        HostileEntry('a', [1]),
      ], eocdEntryCount: 0xFFFE);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('too many entries'),
          ),
        ),
      );
    });

    test('rejects a central directory larger than its cap', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1]),
      ], eocdCentralDirectorySize: 0x7FFFFFFF);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('rejects a central directory that points outside the input', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1]),
      ], eocdCentralDirectoryOffset: 0x7FFFFFF0);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('rejects zip64 markers (our writer never emits them)', () {
      for (final zip in [
        buildHostileZip([
          HostileEntry('a', [1]),
        ], eocdEntryCount: 0xFFFF),
        buildHostileZip([
          HostileEntry('a', [1]),
        ], eocdCentralDirectorySize: 0xFFFFFFFF),
        buildHostileZip([
          HostileEntry('a', [1]),
        ], eocdCentralDirectoryOffset: 0xFFFFFFFF),
      ]) {
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(isA<BoundedExtractionException>()),
        );
      }
    });

    test('accepts an EOCD followed by a comment (spec-legal)', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ], eocdComment: List<int>.filled(300, 0x41));
      expect(BoundedZipExtractor.extract(zip, limits: tiny)['a'], [1, 2, 3]);
    });

    test('rejects when no EOCD exists in the trailing window', () {
      final zip = buildHostileZip([
        HostileEntry('a', [1, 2, 3]),
      ]);
      // Push the EOCD out of the 64 KiB + 22 byte search window with junk.
      final buried = Uint8List.fromList([
        ...zip,
        ...List<int>.filled(70 * 1024, 0),
      ]);
      final roomy = ZipLimits(
        maxEntryBytes: 1024,
        maxTotalBytes: 2048,
        maxEntries: 4,
        maxArchiveBytes: 1024 * 1024,
      );
      expect(
        () => BoundedZipExtractor.extract(buried, limits: roomy),
        throwsA(isA<BoundedExtractionException>()),
      );
    });
  });

  group('M05 — streaming inflate with an output budget', () {
    test('a high-expansion entry is cut off at the budget, not after', () {
      // ~64 KiB of deflate that inflates to 64 MiB (ratio ~1000). Declared
      // size LIES (says 512 bytes) so the header pre-check passes. The
      // extractor must stop inflating at the per-entry cap: the probe
      // records how many bytes were actually produced.
      const bombSize = 64 * 1024 * 1024;
      final zip = buildHostileZip([
        HostileEntry(
          'bomb.bin',
          const <int>[],
          compressedOverride: deflateBombBody(bombSize),
          declaredUncompressedSize: 512,
          declaredCrc32: 0,
        ),
      ]);
      final limits = ZipLimits(
        maxEntryBytes: 1024 * 1024,
        maxTotalBytes: 1024 * 1024,
        maxEntries: 4,
        maxArchiveBytes: 1024 * 1024,
      );
      var produced = -1;
      expect(
        () => BoundedZipExtractor.extract(
          zip,
          limits: limits,
          inflatedBytesProbe: (n) => produced = n,
        ),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('exceeds per-entry cap'),
          ),
        ),
      );
      // The sink refuses BEFORE writing, so what was produced is at most the
      // budget — and certainly not the full 64 MiB. Anything within one
      // 64 KiB deflate block below the budget proves the inflate ran up to
      // the cap and stopped there.
      expect(produced, lessThanOrEqualTo(limits.maxEntryBytes));
      expect(produced, greaterThan(limits.maxEntryBytes - 64 * 1024));
    });

    test('the running total caps the LAST entry by what is left', () {
      // Two truthful 1 KiB entries under a 1.5 KiB total: the second must be
      // rejected while inflating, with at most ~512 bytes produced for it.
      final zip = buildHostileZip([
        HostileEntry('a', List<int>.filled(1024, 1)),
        HostileEntry(
          'b',
          List<int>.filled(1024, 2),
          declaredUncompressedSize: 1,
        ),
      ]);
      final limits = ZipLimits(
        maxEntryBytes: 1024,
        maxTotalBytes: 1536,
        maxEntries: 4,
      );
      var produced = -1;
      expect(
        () => BoundedZipExtractor.extract(
          zip,
          limits: limits,
          inflatedBytesProbe: (n) => produced = n,
        ),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('total exceeds cap'),
          ),
        ),
      );
      expect(produced, lessThanOrEqualTo(1024 + 65536));
    });

    test('declared size lies SMALL: real length still enforced', () {
      final zip = buildHostileZip([
        HostileEntry(
          'x',
          List<int>.filled(2000, 7),
          declaredUncompressedSize: 1,
        ),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('declared size lies LARGE: rejected on the header, no inflate', () {
      final zip = buildHostileZip([
        HostileEntry('x', [1, 2, 3], declaredUncompressedSize: 0x7FFFFFFF),
      ]);
      var produced = 0;
      expect(
        () => BoundedZipExtractor.extract(
          zip,
          limits: tiny,
          inflatedBytesProbe: (n) => produced = n,
        ),
        throwsA(isA<BoundedExtractionException>()),
      );
      expect(produced, 0, reason: 'must not inflate a header-rejected entry');
    });

    test(
      'declared sizes that sum over the total are rejected before inflate',
      () {
        final zip = buildHostileZip([
          HostileEntry('a', List<int>.filled(1000, 1)),
          HostileEntry('b', List<int>.filled(1000, 2)),
          HostileEntry('c', List<int>.filled(1000, 3)),
        ]);
        var produced = 0;
        expect(
          () => BoundedZipExtractor.extract(
            zip,
            limits: tiny, // total 2048
            inflatedBytesProbe: (n) => produced += n,
          ),
          throwsA(isA<BoundedExtractionException>()),
        );
        expect(produced, lessThanOrEqualTo(2000));
      },
    );

    test('stored (method 0) entries obey the same caps', () {
      final zip = buildHostileZip([
        HostileEntry(
          'x',
          List<int>.filled(1500, 9),
          deflate: false,
          declaredUncompressedSize: 10,
        ),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('stored entry whose declared compressed size overruns the input', () {
      // Only the central header can be lied about independently in the
      // builder; declaredCompressedSize applies to both, so the local read
      // overruns the buffer. Must be typed, never a RangeError.
      final zip = buildHostileZip([
        HostileEntry(
          'x',
          [1, 2, 3],
          deflate: false,
          declaredCompressedSize: 5000,
        ),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });
  });

  group(
    'M05 — structural rules reachable only with a hand-built container',
    () {
      test('directory entries are refused', () {
        final zip = buildHostileZip([
          HostileEntry('covers/', const <int>[], deflate: false),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('directory entry'),
            ),
          ),
        );
      });

      test('an empty filename is refused', () {
        final zip = buildHostileZip([
          HostileEntry('', [1, 2, 3]),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('empty filename'),
            ),
          ),
        );
      });

      test('a leaf containing NUL is refused', () {
        final zip = buildHostileZip([
          HostileEntry('a\u0000b', [1, 2, 3]),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('unsafe filename'),
            ),
          ),
        );
      });

      test('two different paths reducing to the same leaf are refused', () {
        final zip = buildHostileZip([
          HostileEntry('a/x', [1]),
          HostileEntry('b/x', [2]),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('duplicate entry name'),
            ),
          ),
        );
      });

      test('two identical central names are refused', () {
        // Header-level parsing keeps both records (the old `Archive` builder
        // silently collapsed same-named entries); the per-entry duplicate
        // rule must therefore see and refuse the second one.
        final zip = buildHostileZip([
          HostileEntry('x', [1]),
          HostileEntry('x', [2]),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('duplicate entry name'),
            ),
          ),
        );
      });

      test('EOCD count lying LOW still trips the real per-entry count', () {
        final zip = buildHostileZip([
          for (var i = 0; i < 5; i++) HostileEntry('e$i', [i]),
        ], eocdEntryCount: 1);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny), // maxEntries 4
          throwsA(
            isA<BoundedExtractionException>().having(
              (e) => e.message,
              'message',
              contains('too many entries'),
            ),
          ),
        );
      });

      test('deflate STORED blocks (level 0) obey the budget too', () {
        // Level-0 deflate emits stored blocks, which the inflater copies via
        // writeInputStream — a different sink path from Huffman output.
        final data = List<int>.filled(1500, 5);
        final zip = buildHostileZip([
          HostileEntry(
            'x',
            data,
            compressedOverride: io.ZLibEncoder(
              raw: true,
              level: 0,
            ).convert(data),
            declaredUncompressedSize: 10,
          ),
        ]);
        var produced = -1;
        expect(
          () => BoundedZipExtractor.extract(
            zip,
            limits: tiny, // per-entry 1024
            inflatedBytesProbe: (n) => produced = n,
          ),
          throwsA(isA<BoundedExtractionException>()),
        );
        expect(produced, lessThanOrEqualTo(1024));
        // And an honest level-0 entry under the cap decodes correctly.
        final small = List<int>.filled(500, 6);
        final ok = buildHostileZip([
          HostileEntry(
            'y',
            small,
            compressedOverride: io.ZLibEncoder(
              raw: true,
              level: 0,
            ).convert(small),
          ),
        ]);
        expect(BoundedZipExtractor.extract(ok, limits: tiny)['y'], small);
      });

      test('stored entry over budget reports zero produced bytes', () {
        final zip = buildHostileZip([
          HostileEntry(
            'x',
            List<int>.filled(1500, 9),
            deflate: false,
            declaredUncompressedSize: 10,
          ),
        ]);
        var produced = -1;
        expect(
          () => BoundedZipExtractor.extract(
            zip,
            limits: tiny,
            inflatedBytesProbe: (n) => produced = n,
          ),
          throwsA(isA<BoundedExtractionException>()),
        );
        expect(produced, 0, reason: 'a stored overrun must not be copied');
        // Honest stored entry: probe reports the full copied length.
        final ok = buildHostileZip([
          HostileEntry('y', List<int>.filled(300, 1), deflate: false),
        ]);
        BoundedZipExtractor.extract(
          ok,
          limits: tiny,
          inflatedBytesProbe: (n) => produced = n,
        );
        expect(produced, 300);
      });
    },
  );

  group('M05 — the decoder itself must never inflate', () {
    test('a UNIX-symlink-flagged bomb is refused without being inflated', () {
      // `ZipDecoder.decodeBytes` reads a symlink's TARGET by inflating its
      // content while still building the Archive — i.e. before any caller
      // check can run, through the unbounded native path. The extractor must
      // therefore not use decodeBytes at all. A symlink entry is refused as
      // "not a regular file", and the probe proves no inflate happened.
      const bombSize = 64 * 1024 * 1024;
      final zip = buildHostileZip([
        HostileEntry(
          'bomb.bin',
          const <int>[],
          compressedOverride: deflateBombBody(bombSize),
          declaredUncompressedSize: 512,
          declaredCrc32: 0,
          versionMadeBy: 3 << 8, // made on UNIX
          externalAttributes: 0xA1FF << 16, // S_IFLNK | 0777
        ),
      ]);
      final limits = ZipLimits(
        maxEntryBytes: 1024 * 1024,
        maxTotalBytes: 1024 * 1024,
        maxEntries: 4,
        maxArchiveBytes: 1024 * 1024,
      );
      var probeCalls = 0;
      final sw = Stopwatch()..start();
      expect(
        () => BoundedZipExtractor.extract(
          zip,
          limits: limits,
          inflatedBytesProbe: (_) => probeCalls++,
        ),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('directory entry'),
          ),
        ),
      );
      expect(probeCalls, 0, reason: 'refused before our inflate ran');
      // A full 64 MiB native inflate costs ~10-20 ms on this machine; the
      // header-only path is sub-millisecond. Generous bound, still a tell.
      expect(sw.elapsedMilliseconds, lessThan(200));
    });

    test('UNIX-made regular files (mode 0100644) are still accepted', () {
      final zip = buildHostileZip([
        HostileEntry(
          'x',
          [1, 2, 3],
          versionMadeBy: 3 << 8,
          externalAttributes: 0x81A4 << 16, // S_IFREG | 0644
        ),
      ]);
      expect(BoundedZipExtractor.extract(zip, limits: tiny)['x'], [1, 2, 3]);
    });

    test('UNIX-made directory entries (mode 040755) are refused', () {
      final zip = buildHostileZip([
        HostileEntry(
          'd',
          const <int>[],
          deflate: false,
          versionMadeBy: 3 << 8,
          externalAttributes: 0x41ED << 16, // S_IFDIR | 0755
        ),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });
  });

  group('M05 — integrity and unsupported features fail closed', () {
    test('CRC-32 mismatch is rejected (corruption is otherwise silent)', () {
      final zip = buildHostileZip([
        HostileEntry(
          'x',
          List<int>.generate(500, (i) => i),
          declaredCrc32: 0x12345678,
        ),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(
          isA<BoundedExtractionException>().having(
            (e) => e.message,
            'message',
            contains('checksum'),
          ),
        ),
      );
    });

    test('flipped body byte is caught by the CRC, not passed through', () {
      // Neither inflater throws on a corrupt deflate stream (verified on the
      // pinned SDK); the CRC is the only detector. Flip one byte inside the
      // compressed body and demand a typed rejection.
      final data = List<int>.generate(4000, (i) => (i * 31) % 251);
      final good = buildHostileZip([HostileEntry('x', data)]);
      // The body starts right after the 30-byte local header + 1-byte name.
      const bodyStart = 31;
      final bodyLen = io.ZLibEncoder(raw: true).convert(data).length;
      var rejected = 0;
      var accepted = 0;
      for (var i = bodyStart + 8; i < bodyStart + bodyLen - 8; i += 7) {
        final bad = Uint8List.fromList(good)..[i] ^= 0x55;
        try {
          final out = BoundedZipExtractor.extract(
            bad,
            limits: ZipLimits(
              maxEntryBytes: 8192,
              maxTotalBytes: 8192,
              maxEntries: 2,
            ),
          );
          // If it decoded, the content MUST equal the original (CRC held).
          expect(out['x'], data);
          accepted++;
        } on BoundedExtractionException {
          rejected++;
        }
      }
      expect(rejected, greaterThan(0));
      // A flip that leaves the stream decodable to the same bytes is
      // astronomically unlikely; allow it but never a wrong payload.
      expect(accepted, lessThanOrEqualTo(1));
    });

    test('encrypted entries (flag bit 0) are refused', () {
      final zip = buildHostileZip([
        HostileEntry('x', [1, 2, 3], flags: 0x1),
      ]);
      expect(
        () => BoundedZipExtractor.extract(zip, limits: tiny),
        throwsA(isA<BoundedExtractionException>()),
      );
    });

    test('unsupported compression methods are refused', () {
      for (final method in [12, 14, 93, 99]) {
        final zip = buildHostileZip([
          HostileEntry('x', [1, 2, 3], method: method),
        ]);
        expect(
          () => BoundedZipExtractor.extract(zip, limits: tiny),
          throwsA(isA<BoundedExtractionException>()),
          reason: 'method $method',
        );
      }
    });

    test(
      'local/central header disagreement never causes a large allocation',
      () {
        // KNOWN RESIDUAL from the old header comment: local header says 4 GiB,
        // central says 3. The streaming path must ignore both for allocation.
        final zip = buildHostileZip([
          HostileEntry(
            'x',
            [1, 2, 3],
            localHeaderOverrides: {'uncompressedSize': 0xFFFFFFFF},
          ),
        ]);
        final out = BoundedZipExtractor.extract(zip, limits: tiny);
        expect(out['x'], [1, 2, 3]);
      },
    );

    test(
      'output is an exact-size copy, not a view over the inflate buffer',
      () {
        final zip = buildHostileZip([
          HostileEntry('x', List<int>.filled(700, 3)),
        ]);
        final out = BoundedZipExtractor.extract(zip, limits: tiny)['x']!;
        expect(out.length, 700);
        expect(out.buffer.lengthInBytes, 700);
      },
    );
  });
}
