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
  });
}
