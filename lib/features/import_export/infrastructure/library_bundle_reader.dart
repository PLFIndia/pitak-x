/// Reads a "Pitaka bundle" (.zip): the canonical re-importable JSON plus the
/// actual local cover images. Pure-logic-where-possible port of Kotlin
/// `LibraryBundle.read` (source app).
///
/// Layout (flat, shared with the backup archive):
///   library.json     the PitakaExport
///   cover_<leaf>     one entry per referenced LOCAL cover file
///
/// A bundle is MERGED (additive), never restored destructively, and carries
/// zero vault data. The reader: bounded-extracts the ZIP, writes the bundled
/// covers into the covers dir (ADDITIVE — never wipes existing covers), then
/// parses library.json with keepLocalCovers=true so the local references
/// resolve against the files just written.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/infrastructure/cover_paths.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';

/// ZIP entry name of the bundled library JSON.
const String kBundleLibraryJsonEntry = 'library.json';

/// Prefix of a bundled cover entry (Kotlin `BackupArchive.COVER_ENTRY_PREFIX`).
const String kBundleCoverEntryPrefix = 'cover_';

/// Reads Pitaka bundle archives into an [ImportPayload], writing covers to
/// disk.
final class LibraryBundleReader {
  /// Creates a reader that writes covers under `coversDir` (typically
  /// `<appDocsDir>/covers`). The directory is created if missing.
  const LibraryBundleReader({required this.coversDir});

  /// Absolute path to the covers directory covers are written into.
  final String coversDir;

  /// Reads [zipBytes]: bounded-extract, write bundled covers (additive), then
  /// parse `library.json` keeping local cover refs. Fails closed with a typed
  /// [Failure] on a hostile/corrupt archive or a missing JSON entry.
  Future<Either<Failure, ImportPayload>> read(Uint8List zipBytes) async {
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(zipBytes);
    } on BoundedExtractionException catch (e) {
      return left(BackupCorruptFailure(e.message));
    }

    final jsonBytes = files[kBundleLibraryJsonEntry];
    if (jsonBytes == null) {
      return left(const BackupCorruptFailure('Bundle missing library.json'));
    }

    // Write bundled covers into place BEFORE parsing, so kept local references
    // point at real files. Best-effort per cover: one bad entry must not fail
    // the whole import. Re-validate the leaf via CoverPaths (defence in depth —
    // the extractor already sanitised it).
    final dir = Directory(coversDir);
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } on FileSystemException catch (e) {
      return left(StorageFailure('Could not create covers dir: ${e.message}'));
    }

    for (final entry in files.entries) {
      final name = entry.key;
      if (!name.startsWith(kBundleCoverEntryPrefix)) continue;
      final leaf = name.substring(kBundleCoverEntryPrefix.length);
      if (CoverPaths.leafOf('${CoverPaths.prefix}$leaf') != leaf) continue;
      try {
        File(p.join(coversDir, leaf)).writeAsBytesSync(entry.value);
      } on FileSystemException {
        // Best effort: skip an unwritable cover, keep importing.
        continue;
      }
    }

    const importer = PitakaJsonImporter(keepLocalCovers: true);
    // UTF-8 decode (allowMalformed) so Devanagari/Unicode titles survive; never
    // String.fromCharCodes, which mangles multi-byte sequences.
    final json = utf8.decode(jsonBytes, allowMalformed: true);
    final payload = importer.parse(json);
    return right(payload);
  }
}
