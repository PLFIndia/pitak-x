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
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';

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
    final payload = PitakaJsonImporter(
      keepLocalCovers: true,
      limits: limits,
    ).parse(text);
    // The shared parser owns the version rule. Check its typed verdict before
    // collection gates so an unfamiliar future shape keeps the update message.
    final schemaTooNewFailure = payload.schemaTooNewFailure;
    if (schemaTooNewFailure != null) {
      return left(schemaTooNewFailure);
    }
    // Tolerant text imports may skip malformed collections/rows. A bundle
    // must not install images for rows that silently disappeared while parsing.
    // S5 (H4): `periodicals` is a valid third collection — a v4 bundle that
    // carries ONLY magazine titles is a real (if unusual) backup, and the
    // pre-S5 reader rejected it as "invalid collections".
    const collections = ['books', 'wishlist', 'periodicals'];
    if (decoded is! Map<String, dynamic> ||
        !collections.any(decoded.containsKey)) {
      return left(const BackupCorruptFailure('Invalid bundle collections.'));
    }
    // Shape-check every present collection before applying the payload: a
    // malformed `periodicals` must never degrade into an empty series list,
    // because the import would then restore its issues as books.
    for (final key in collections) {
      if (!decoded.containsKey(key)) continue;
      final rows = decoded[key];
      if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
        return left(const BackupCorruptFailure('Invalid bundle rows.'));
      }
    }
    final covers = <String, Uint8List>{};
    for (final entry in files.entries) {
      if (!entry.key.startsWith(kBundleCoverEntryPrefix)) continue;
      final leaf = entry.key.substring(kBundleCoverEntryPrefix.length);
      covers[leaf] = entry.value;
    }
    return ImportBundle.validate(payload, covers);
  }
}
