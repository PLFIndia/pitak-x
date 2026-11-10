import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';
import 'package:pitaka/features/backup/infrastructure/backup_zip_file.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';

/// BR4 (review finding P3-B1): the ZIP of a backup is written straight to a
/// file. These tests drive the packer alone, with entries made by hand, so
/// each rule can be seen without a whole library:
///  - what goes in comes out byte for byte, through the app's OWN reader;
///  - the shape of each kind of entry is the one the design chose;
///  - a file with the final name exists only for a complete backup.
void main() {
  late Directory tmp;
  late String partPath;
  late String finalPath;

  // Room for everything these tests pack.
  const limits = BackupLimits(
    maxCovers: 16,
    maxContentBytes: 64 * 1024 * 1024,
    maxCoverBytes: 4 * 1024 * 1024,
    maxDatabaseBytes: 16 * 1024 * 1024,
    maxTextEntryBytes: 4 * 1024 * 1024,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_zip_file_test');
    Directory('${tmp.path}/scratch').createSync();
    partPath = '${tmp.path}/scratch/backup.part';
    finalPath = '${tmp.path}/Pitak-backup-20261110-193000.pitabak';
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Bytes that do not shrink under deflate, like a JPEG.
  Uint8List noise(int length, {int seed = 1}) {
    final random = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Bytes that shrink well, like a database full of similar rows.
  Uint8List rows(int length) => Uint8List.fromList(
    List<int>.generate(length, (i) => 'row of a book '.codeUnitAt(i % 14)),
  );

  PlannedBackupEntry text(String name, Uint8List bytes) =>
      PlannedBackupEntry(name, bytes.length, () => bytes);

  /// A cover: read whole from its file when its turn comes.
  PlannedBackupEntry cover(String name, Uint8List bytes) {
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return PlannedBackupEntry(
      'cover_$name',
      bytes.length,
      file.readAsBytesSync,
    );
  }

  /// A database: streamed from its file.
  PlannedBackupEntry database(String name, Uint8List bytes) {
    final file = File('${tmp.path}/scratch/$name')..writeAsBytesSync(bytes);
    return PlannedBackupEntry.streamed(name, bytes.length, file.path);
  }

  PackedBackup pack(List<PlannedBackupEntry> entries, {int? maxArchiveBytes}) =>
      packBackupZip(
        entries: entries,
        partPath: partPath,
        finalPath: finalPath,
        maxArchiveBytes: maxArchiveBytes ?? limits.maxArchiveBytes,
      );

  Map<String, Uint8List> readBack() => BoundedZipExtractor.extract(
    File(finalPath).readAsBytesSync(),
    limits: ZipLimits.forBackup(limits),
  );

  /// The directory records of the finished file, by entry name.
  Map<String, ZipDirectoryEntry> directory() {
    final bytes = File(finalPath).readAsBytesSync();
    final end = ZipContainer.locateEndRecord(bytes);
    expect(end.isZip64, isFalse);
    return {
      for (final entry in ZipContainer.directory(bytes, end)) entry.name: entry,
    };
  }

  const methodStored = 0;
  const methodDeflate = 8;
  const flagSizesBehindData = 0x8;

  test('every entry comes back byte for byte through the app reader, in '
      'the order given', () {
    final manifest = Uint8List.fromList('{"schemaVersion":1}'.codeUnits);
    final books = rows(300 * 1024);
    final picture = noise(20 * 1024);
    final network = Uint8List.fromList('{"libraries":[]}'.codeUnits);

    final packed = pack([
      text('manifest.json', manifest),
      database('books.db', books),
      cover('a.jpg', picture),
      text('network.json', network),
    ]);

    expect(packed.inPlace, isTrue);
    expect(packed.sizeBytes, File(finalPath).lengthSync());
    expect(File(partPath).existsSync(), isFalse, reason: 'moved, not copied');

    final files = readBack();
    expect(files.keys.toList(), [
      'manifest.json',
      'books.db',
      'cover_a.jpg',
      'network.json',
    ]);
    expect(files['manifest.json'], manifest);
    expect(files['books.db'], books);
    expect(files['cover_a.jpg'], picture);
    expect(files['network.json'], network);
  });

  test('the shape of each kind of entry: text deflated, database deflated '
      'with its sizes behind the data, cover stored', () {
    // Pinned on purpose: an update of `package:archive` that changes how an
    // entry is written must be noticed and looked at, not slip through.
    final picture = noise(20 * 1024);
    pack([
      text('manifest.json', rows(4096)),
      database('books.db', rows(300 * 1024)),
      cover('a.jpg', picture),
    ]);

    final entries = directory();

    final manifest = entries['manifest.json']!;
    expect(manifest.method, methodDeflate);
    expect(manifest.flags & flagSizesBehindData, 0);
    expect(manifest.compressedSize, lessThan(manifest.uncompressedSize));

    final books = entries['books.db']!;
    expect(books.method, methodDeflate);
    expect(books.flags & flagSizesBehindData, flagSizesBehindData);
    expect(books.uncompressedSize, 300 * 1024);
    expect(books.compressedSize, lessThan(books.uncompressedSize));

    final stored = entries['cover_a.jpg']!;
    expect(stored.method, methodStored);
    expect(stored.flags & flagSizesBehindData, 0);
    expect(stored.compressedSize, picture.length);
    expect(stored.uncompressedSize, picture.length);
  });

  test('a database larger than the read buffers and a cover larger than '
      '1 MiB come back whole', () {
    // 3 MiB crosses the 1 MiB buffers of the file streams several times;
    // a stored entry above 1 MiB takes another path inside the package.
    final books = rows(3 * 1024 * 1024 + 123);
    final picture = noise(1024 * 1024 + 4567, seed: 2);

    pack([database('books.db', books), cover('big.jpg', picture)]);

    final files = readBack();
    expect(files['books.db'], books);
    expect(files['cover_big.jpg'], picture);
  });

  test('a database that does not shrink comes back whole', () {
    // The vault file is ciphertext: deflate cannot make it smaller.
    final vault = noise(700 * 1024, seed: 3);

    pack([database('borrowers.db', vault)]);

    expect(readBack()['borrowers.db'], vault);
  });

  test('entries without content come back empty', () {
    pack([
      text('manifest.json', Uint8List(0)),
      database('books.db', Uint8List(0)),
      cover('empty.jpg', Uint8List(0)),
    ]);

    final files = readBack();
    expect(files, hasLength(3));
    expect(files['manifest.json'], isEmpty);
    expect(files['books.db'], isEmpty);
    expect(files['cover_empty.jpg'], isEmpty);
  });

  group('the archive cap', () {
    late int size;

    setUp(() {
      size = pack([cover('a.jpg', noise(5000))]).sizeBytes;
      File(finalPath).deleteSync();
    });

    test('exactly at the cap the file is put in place', () {
      final packed = pack([cover('a.jpg', noise(5000))], maxArchiveBytes: size);

      expect(packed, (sizeBytes: size, inPlace: true));
      expect(File(finalPath).lengthSync(), size);
    });

    test('one byte over, nothing gets the final name and the size is '
        'reported', () {
      final packed = pack([
        cover('a.jpg', noise(5000)),
      ], maxArchiveBytes: size - 1);

      expect(packed, (sizeBytes: size, inPlace: false));
      expect(File(finalPath).existsSync(), isFalse);
    });
  });

  group('when something goes wrong, no file gets the final name', () {
    test('a database file that is missing', () {
      expect(
        () => pack([
          text('manifest.json', rows(10)),
          PlannedBackupEntry.streamed(
            'books.db',
            10,
            '${tmp.path}/scratch/nowhere.db',
          ),
        ]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(finalPath).existsSync(), isFalse);
    });

    test('a database that is no longer the size the checks judged', () {
      final planned = database('books.db', rows(1000));
      // The file changes after it was measured.
      File(planned.streamPath!).writeAsBytesSync(rows(1001));

      expect(
        () => pack([planned]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('changed size'),
          ),
        ),
      );
      expect(File(finalPath).existsSync(), isFalse);
    });

    test('a cover that is no longer the size the checks judged', () {
      final picture = File('${tmp.path}/a.jpg')..writeAsBytesSync(noise(500));
      final planned = PlannedBackupEntry(
        'cover_a.jpg',
        500,
        picture.readAsBytesSync,
      );
      picture.writeAsBytesSync(noise(499));

      expect(
        () => pack([text('manifest.json', rows(10)), planned]),
        throwsA(isA<StateError>()),
      );
      expect(File(finalPath).existsSync(), isFalse);
    });

    test('a cover file that is missing', () {
      expect(
        () => pack([
          PlannedBackupEntry(
            'cover_gone.jpg',
            3,
            File('${tmp.path}/gone.jpg').readAsBytesSync,
          ),
        ]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(finalPath).existsSync(), isFalse);
    });

    test('a final name that cannot be taken', () {
      // A folder already sits where the finished file should go.
      Directory(finalPath).createSync();

      expect(
        () => pack([cover('a.jpg', noise(100))]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(finalPath).existsSync(), isFalse);
      expect(Directory(finalPath).listSync(), isEmpty);
    });
  });

  // BR4 rider 3: the packer counts the cover pictures it has written, so
  // that the page can say "Cover 1,234 of 9,000". It reports EVERY cover;
  // how many of these reports are passed on is decided by its caller
  // (`backup_progress_port_test.dart`).
  group('counting the covers (progress)', () {
    late List<(int, int)> counted;

    setUp(() => counted = []);

    PackedBackup packCounting(List<PlannedBackupEntry> entries) =>
        packBackupZip(
          entries: entries,
          partPath: partPath,
          finalPath: finalPath,
          maxArchiveBytes: limits.maxArchiveBytes,
          onCoverPacked: (done, total) => counted.add((done, total)),
        );

    test('one call after every cover, with the running count and the '
        'number of covers; other entries do not count', () {
      final packed = packCounting([
        text('manifest.json', rows(10)),
        database('books.db', rows(1000)),
        cover('a.jpg', noise(100)),
        cover('b.jpg', noise(200, seed: 2)),
        cover('c.jpg', noise(300, seed: 3)),
        text('network.json', rows(10)),
      ]);

      expect(packed.inPlace, isTrue);
      expect(counted, [(1, 3), (2, 3), (3, 3)]);
      expect(readBack(), hasLength(6), reason: 'the archive is unchanged');
    });

    test('a backup without covers is never counted', () {
      packCounting([
        text('manifest.json', rows(10)),
        database('books.db', rows(1000)),
      ]);

      expect(counted, isEmpty);
    });

    test('a cover is counted when it is IN the archive: one that fails is '
        'not', () {
      expect(
        () => packCounting([
          cover('a.jpg', noise(100)),
          PlannedBackupEntry(
            'cover_gone.jpg',
            3,
            File('${tmp.path}/gone.jpg').readAsBytesSync,
          ),
          cover('c.jpg', noise(300, seed: 3)),
        ]),
        throwsA(isA<FileSystemException>()),
      );

      expect(counted, [(1, 3)]);
      expect(File(finalPath).existsSync(), isFalse);
    });
  });
}
