import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';

void main() {
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
