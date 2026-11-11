/// The ZIP readers of the app behind ONE shape, so that the same test cases
/// can be run against each of them (backup rework BR5).
///
/// WHY THIS FILE EXISTS (beginner note): the app has two ZIP readers until
/// the older one is removed (BR7). `BoundedZipExtractor` holds the whole
/// archive in memory; `BoundedZipFile` works from a file on disk. A file
/// that one of them refuses and the other accepts by accident would be a
/// hole, so the tests in `bounded_zip_extractor_test.dart` and
/// `bounded_zip_extractor_container_test.dart` run every case against every
/// reader in [zipReadersUnderTest]. Where a verdict differs ON PURPOSE the
/// case says so by name and asks [ZipReaderUnderTest.fromFile].
///
/// (Not called `…_test.dart`: `flutter test` would take it for a test.)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

/// "These bytes, these limits: the entries by name, or a
/// `BoundedExtractionException`." The probe is the test seam of the readers:
/// it is told how many bytes were unpacked for the entry that was being
/// worked on when the reader stopped.
typedef ZipExtractForTest =
    Map<String, Uint8List> Function(
      Uint8List zip, {
      ZipLimits? limits,
      void Function(int producedBytes)? inflatedBytesProbe,
    });

/// One reader, with the name its test group gets.
final class ZipReaderUnderTest {
  /// Creates the description of one reader.
  const ZipReaderUnderTest({
    required this.name,
    required this.extract,
    required this.fromFile,
  });

  /// Shown in the name of every test that runs against this reader.
  final String name;

  /// Runs the reader on an archive held in memory.
  final ZipExtractForTest extract;

  /// True for the reader that works from a file. It is STRICTER than the
  /// in-memory reader in three rules (BR5: N1, the unpacked size is the
  /// declared one; N2, the entry header carries the directory's name; N3,
  /// no zip64 value on an entry), and it stops a lying entry at its
  /// declared size instead of at the cap. A case whose outcome depends on
  /// one of these asks this flag and states both outcomes.
  final bool fromFile;
}

/// Every ZIP reader the app ships.
const List<ZipReaderUnderTest> zipReadersUnderTest = [
  ZipReaderUnderTest(
    name: 'reader in memory',
    extract: BoundedZipExtractor.extract,
    fromFile: false,
  ),
  ZipReaderUnderTest(
    name: 'reader from a file',
    extract: _extractFromFile,
    fromFile: true,
  ),
];

/// What one way of taking every entry gave: the entries, or the refusal.
typedef _Outcome = ({Map<String, Uint8List>? entries, String? refusal});

/// Runs `BoundedZipFile` on [zip] the way the in-memory reader is run:
/// everything out, or one typed refusal.
///
/// The archive is written to a temporary file first. Then every entry is
/// taken TWICE, once into memory (`read`) and once into a file (`writeTo`),
/// and the two ways must agree: the same content, or the same refusal. So
/// every case of the shared tests also checks that the two ways of taking
/// an entry cannot differ.
Map<String, Uint8List> _extractFromFile(
  Uint8List zip, {
  ZipLimits? limits,
  void Function(int producedBytes)? inflatedBytesProbe,
}) {
  final caps = limits ?? ZipLimits.pitakaBackup;
  final folder = Directory.systemTemp.createTempSync('zip_reader_table');
  try {
    final path = '${folder.path}/archive.zip';
    File(path).writeAsBytesSync(zip);

    _Outcome run(
      void Function(int)? probe,
      Uint8List Function(BoundedZipFile file, ZipFileEntry entry, int index)
      take,
    ) {
      try {
        final file = BoundedZipFile.open(
          path,
          limits: caps,
          unpackedBytesProbe: probe,
        );
        try {
          final out = <String, Uint8List>{};
          for (var i = 0; i < file.entries.length; i++) {
            final entry = file.entries[i];
            out[entry.name] = take(file, entry, i);
          }
          return (entries: out, refusal: null);
        } finally {
          file.close();
        }
      } on BoundedExtractionException catch (e) {
        return (entries: null, refusal: e.message);
      }
    }

    final intoMemory = run(
      inflatedBytesProbe,
      (file, entry, _) => file.read(entry, maxBytes: caps.maxEntryBytes),
    );
    final intoFiles = run(null, (file, entry, index) {
      final target = File('${folder.path}/entry_$index');
      try {
        file.writeTo(entry, target.path);
      } on BoundedExtractionException {
        // A refused entry must not leave its half-written file behind.
        expect(target.existsSync(), isFalse, reason: 'left: ${entry.name}');
        rethrow;
      }
      return target.readAsBytesSync();
    });

    expect(
      intoFiles.refusal,
      intoMemory.refusal,
      reason: '`writeTo` and `read` must refuse alike',
    );
    expect(
      intoFiles.entries,
      intoMemory.entries,
      reason: '`writeTo` and `read` must give the same content',
    );

    final refusal = intoMemory.refusal;
    if (refusal != null) throw BoundedExtractionException(refusal);
    return intoMemory.entries!;
  } finally {
    folder.deleteSync(recursive: true);
  }
}
