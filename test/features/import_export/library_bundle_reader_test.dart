import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';

void main() {
  late Directory tempDir;
  late String coversDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('bundle_test');
    coversDir = '${tempDir.path}/covers';
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Uint8List bundleOf(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  group('LibraryBundleReader', () {
    test('reads library.json and writes bundled covers to disk', () async {
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'गोदान', 'coverUrl': 'covers/uuid-1.jpg'},
        ],
        'wishlist': <dynamic>[],
      });
      final zip = bundleOf({
        'library.json': utf8.encode(json),
        'cover_uuid-1.jpg': [9, 9, 9],
      });

      final reader = LibraryBundleReader(coversDir: coversDir);
      final result = await reader.read(zip);

      final payload = result.getOrElse((_) => throw StateError('expected ok'));
      // Local cover ref is KEPT (bundle path), Unicode title survives.
      expect(payload.books.single.title, 'गोदान');
      expect(payload.books.single.coverUrl, 'covers/uuid-1.jpg');
      // The cover file was written into place.
      expect(File('$coversDir/uuid-1.jpg').readAsBytesSync(), [9, 9, 9]);
    });

    test('fails closed when library.json is missing', () async {
      final zip = bundleOf({
        'cover_x.jpg': [1],
      });
      final reader = LibraryBundleReader(coversDir: coversDir);
      final result = await reader.read(zip);
      result.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected a corrupt failure'),
      );
    });

    test('maps a hostile/corrupt archive to BackupCorruptFailure', () async {
      final reader = LibraryBundleReader(coversDir: coversDir);
      final result = await reader.read(Uint8List.fromList([0, 1, 2]));
      result.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected a corrupt failure'),
      );
    });
  });
}
