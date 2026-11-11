/// The ZIP readers of the app behind ONE shape, so that the same test cases
/// can be run against each of them (backup rework BR5).
///
/// WHY THIS FILE EXISTS (beginner note): the app is getting a second ZIP
/// reader, one that works from a FILE instead of holding the whole archive
/// in memory. Until the old reader is removed (BR7), both ship. A file that
/// one of them refuses and the other accepts would be a hole, so the tests
/// in `bounded_zip_extractor_test.dart` and
/// `bounded_zip_extractor_container_test.dart` run every case against every
/// reader in [zipReadersUnderTest]. Where a verdict differs ON PURPOSE the
/// case says so by name.
library;

import 'dart:typed_data';

import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';

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
  const ZipReaderUnderTest({required this.name, required this.extract});

  /// Shown in the name of every test that runs against this reader.
  final String name;

  /// Runs the reader on an archive held in memory.
  final ZipExtractForTest extract;
}

/// Every ZIP reader the app ships.
const List<ZipReaderUnderTest> zipReadersUnderTest = [
  ZipReaderUnderTest(
    name: 'reader in memory',
    extract: BoundedZipExtractor.extract,
  ),
];
