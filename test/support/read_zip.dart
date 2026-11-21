/// "This ZIP, these limits: every entry by name, or the refusal."
///
/// WHY THIS FILE EXISTS (beginner note): the app's ZIP reader,
/// `BoundedZipFile`, hands out one entry at a time, and a restore takes
/// only the entries it has a rule for. A test often wants something
/// simpler: everything that is in an archive, to look at it, or the one
/// typed refusal. [readZip] and [readZipFile] give that, with the real
/// reader and nothing else. (Until backup rework BR7 the tests asked a
/// second reader for it, `BoundedZipExtractor`, which held the whole
/// archive in memory. It was removed; ADR 0009, third amendment.)
///
/// Every entry is taken TWICE, once into memory (`read`) and once into a
/// new file (`writeTo`), and the two ways must agree: the same content,
/// or the same refusal. So every test that reads an archive through this
/// file also checks that the two ways of taking an entry cannot differ.
///
/// (Not called `…_test.dart`: `flutter test` would take it for a test.)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

/// What one way of taking every entry gave: the entries, or the refusal.
typedef _Outcome = ({Map<String, Uint8List>? entries, String? refusal});

/// Every entry of the archive [zip], by its leaf name.
///
/// [limits] defaults to the limits of a Pitak backup. No rule per entry
/// name is given, so every entry is taken, up to
/// [ZipLimits.maxEntryBytes].
///
/// [unpackedBytesProbe] is the reader's test seam: it is told how many
/// bytes were unpacked for an entry each time one was worked on (taken, or
/// refused half-way). It hears of the first pass (`read`) only.
///
/// Throws [BoundedExtractionException] when the reader refuses the
/// archive or one of its entries.
Map<String, Uint8List> readZip(
  Uint8List zip, {
  ZipLimits? limits,
  void Function(int unpackedBytes)? unpackedBytesProbe,
}) {
  final folder = Directory.systemTemp.createTempSync('read_zip_source');
  try {
    final path = '${folder.path}/archive.zip';
    File(path).writeAsBytesSync(zip);
    return readZipFile(
      path,
      limits: limits,
      unpackedBytesProbe: unpackedBytesProbe,
    );
  } finally {
    folder.deleteSync(recursive: true);
  }
}

/// [readZip] for an archive that already is a file. The file is only read.
Map<String, Uint8List> readZipFile(
  String path, {
  ZipLimits? limits,
  void Function(int unpackedBytes)? unpackedBytesProbe,
}) {
  final caps = limits ?? ZipLimits.pitakaBackup;
  final folder = Directory.systemTemp.createTempSync('read_zip_entries');
  try {
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
      unpackedBytesProbe,
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
      final content = target.readAsBytesSync();
      // One entry on disk at a time: an archive with thousands of entries
      // must not fill the temporary folder.
      target.deleteSync();
      return content;
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

/// A second opinion: the entries of the HONEST archive [zip] as the ZIP
/// reader of `package:archive` gives them, by their name in the archive.
///
/// For tests that say "our reader takes this file byte for byte": they
/// need something to compare with that is not our reader. Never for odd
/// or hostile files. The package's reader has no limits, and what it
/// accepts changes between its versions, which is why the app does not
/// use it (ADR 0009).
Map<String, Uint8List> readZipWithPackage(Uint8List zip) => {
  for (final file in ZipDecoder().decodeBytes(zip)) file.name: file.content,
};
