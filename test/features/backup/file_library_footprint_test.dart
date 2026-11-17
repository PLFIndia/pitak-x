import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/infrastructure/file_library_footprint.dart';

/// BR9: the size of the library on disk, for the notice before a backup
/// and before a restore. Real folders in a temporary directory.
///
/// What these tests guard:
///  - the three sums: the catalogue with SQLite's side files, the covers,
///    and everything else (the vault);
///  - a library without covers, or without a vault, is not an error;
///  - what cannot be read is "null", never a throw;
///  - nothing is written or changed.
void main() {
  late Directory docs;
  late DataGeneration generation;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('library_footprint_test');
    // The real store makes the folder the app would use (`gen-000001`).
    generation = DataGenerations(docsDir: docs.path).open();
  });

  tearDown(() {
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  void put(String relativePath, int bytes) {
    File(p.join(generation.path, relativePath))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(bytes, 7));
  }

  LibraryFootprintJob job() => (
    generationDir: generation.path,
    catalogueDbName: p.basename(generation.catalogueDbPath),
    coversDir: generation.coversDir,
  );

  FileLibraryFootprintSource source() =>
      FileLibraryFootprintSource(activeGeneration: () async => generation);

  /// Every file under the generation with its size, to prove that a read
  /// changes nothing.
  Map<String, int> snapshot() => {
    for (final file in Directory(
      generation.path,
    ).listSync(recursive: true).whereType<File>())
      p.relative(file.path, from: generation.path): file.lengthSync(),
  };

  group('measureLibraryFootprint', () {
    test('a fresh, empty library: nothing but the marker file', () {
      final footprint = measureLibraryFootprint(job());

      expect(footprint.catalogueBytes, 0);
      expect(footprint.coverBytes, 0);
      // The store's marker of a complete generation is the only file.
      final marker = snapshot().values.fold<int>(0, (a, b) => a + b);
      expect(footprint.vaultBytes, marker);
    });

    test('the catalogue counts with the side files SQLite keeps next to '
        'it', () {
      final before = measureLibraryFootprint(job());
      put('pitaka.db', 1000);
      put('pitaka.db-wal', 300);
      put('pitaka.db-shm', 20);
      put('pitaka.db-journal', 4);

      final footprint = measureLibraryFootprint(job());

      expect(footprint.catalogueBytes, 1324);
      expect(footprint.coverBytes, 0);
      expect(footprint.vaultBytes, before.vaultBytes);
    });

    test('every file of the covers folder counts as a cover', () {
      put('covers/a.jpg', 500);
      put('covers/b.jpg', 70);
      put('covers/c.png', 3);

      expect(measureLibraryFootprint(job()).coverBytes, 573);
    });

    test('every other file of the generation counts as the vault', () {
      final before = measureLibraryFootprint(job());
      put('borrowers.db', 4096);
      put('borrowers.db-wal', 100);
      put('vault_backup_blob', 200);
      put('vault_biometric_blob', 50);

      final footprint = measureLibraryFootprint(job());

      expect(footprint.vaultBytes - before.vaultBytes, 4446);
      expect(footprint.catalogueBytes, 0);
      expect(footprint.coverBytes, 0);
    });

    test('all three together, and the total', () {
      final before = measureLibraryFootprint(job());
      put('pitaka.db', 1000);
      put('covers/a.jpg', 500);
      put('borrowers.db', 4096);

      final footprint = measureLibraryFootprint(job());

      expect(footprint.catalogueBytes, 1000);
      expect(footprint.coverBytes, 500);
      expect(footprint.vaultBytes, before.vaultBytes + 4096);
      expect(footprint.totalBytes, 5596 + before.vaultBytes);
    });

    test('a folder inside the covers folder is not followed', () {
      put('covers/a.jpg', 500);
      put('covers/nested/deep.jpg', 9000);

      expect(measureLibraryFootprint(job()).coverBytes, 500);
    });

    test('a covers folder that does not exist counts as empty', () {
      put('pitaka.db', 1000);
      final covers = Directory(generation.coversDir);
      if (covers.existsSync()) covers.deleteSync(recursive: true);

      final footprint = measureLibraryFootprint(job());

      expect(footprint.coverBytes, 0);
      expect(footprint.catalogueBytes, 1000);
    });

    test('a generation folder that is gone throws for the caller to '
        'handle', () {
      Directory(generation.path).deleteSync(recursive: true);

      expect(
        () => measureLibraryFootprint(job()),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('measuring changes nothing on disk', () {
      put('pitaka.db', 1000);
      put('covers/a.jpg', 500);
      put('borrowers.db', 4096);
      final before = snapshot();

      measureLibraryFootprint(job());

      expect(snapshot(), before);
    });
  });

  group('FileLibraryFootprintSource', () {
    test('reads the generation in use, through the worker', () async {
      put('pitaka.db', 1000);
      put('covers/a.jpg', 500);

      final footprint = await source().read();

      expect(footprint, isNotNull);
      expect(footprint!.catalogueBytes, 1000);
      expect(footprint.coverBytes, 500);
    });

    test('asks for the generation at every read (a restore switches '
        'it)', () async {
      var asked = 0;
      final counting = FileLibraryFootprintSource(
        activeGeneration: () async {
          asked++;
          return generation;
        },
      );

      await counting.read();
      await counting.read();

      expect(asked, 2);
    });

    test('a generation that cannot be resolved: null, not a throw', () async {
      final failing = FileLibraryFootprintSource(
        activeGeneration: () async => throw StateError('no generation'),
      );

      expect(await failing.read(), isNull);
    });

    test('a generation folder that is gone: null, not a throw', () async {
      Directory(generation.path).deleteSync(recursive: true);

      expect(await source().read(), isNull);
    });
  });
}
