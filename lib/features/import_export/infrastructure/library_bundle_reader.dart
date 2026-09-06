/// Decodes a Pitaka bundle without touching the filesystem. Incoming names
/// identify bundled bytes only; the import transaction assigns fresh names.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';

/// ZIP entry name of the bundled library JSON.
const String kBundleLibraryJsonEntry = 'library.json';

/// Prefix of a bundled cover entry (Kotlin `BackupArchive.COVER_ENTRY_PREFIX`).
const String kBundleCoverEntryPrefix = 'cover_';

/// Parses bundle metadata and validates all local image references first.
final class LibraryBundleReader implements BundleReader {
  /// Creates a side-effect-free reader using the existing import limits.
  const LibraryBundleReader({this.limits = ImportLimits.defaults});

  /// Catalogue parsing limits; decompression limits remain in the extractor.
  final ImportLimits limits;

  @override
  Future<Either<Failure, ImportBundle>> read(Uint8List zipBytes) async {
    final Map<String, Uint8List> files;
    try {
      files = BoundedZipExtractor.extract(zipBytes);
    } on BoundedExtractionException {
      return left(const BackupCorruptFailure('Could not read bundle archive.'));
    }
    final jsonBytes = files[kBundleLibraryJsonEntry];
    if (jsonBytes == null) {
      return left(const BackupCorruptFailure('Bundle missing library.json.'));
    }
    final String text;
    final Object? decoded;
    try {
      text = utf8.decode(jsonBytes);
      if (text.length > limits.maxTextChars) {
        return left(
          const BackupCorruptFailure('Bundle catalogue is too large.'),
        );
      }
      decoded = jsonDecode(text);
    } on FormatException {
      return left(const BackupCorruptFailure('Invalid bundle catalogue.'));
    }
    // Tolerant text imports may skip malformed collections/rows. A bundle
    // must not install images for rows that silently disappeared while parsing.
    if (decoded is! Map<String, dynamic> ||
        !['books', 'wishlist'].any(decoded.containsKey)) {
      return left(const BackupCorruptFailure('Invalid bundle collections.'));
    }
    for (final key in ['books', 'wishlist']) {
      if (!decoded.containsKey(key)) continue;
      final rows = decoded[key];
      if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
        return left(const BackupCorruptFailure('Invalid bundle rows.'));
      }
    }
    final payload = PitakaJsonImporter(
      keepLocalCovers: true,
      limits: limits,
    ).parse(text);
    final covers = <String, Uint8List>{};
    for (final entry in files.entries) {
      if (!entry.key.startsWith(kBundleCoverEntryPrefix)) continue;
      final leaf = entry.key.substring(kBundleCoverEntryPrefix.length);
      covers[leaf] = entry.value;
    }
    return ImportBundle.validate(payload, covers);
  }
}
