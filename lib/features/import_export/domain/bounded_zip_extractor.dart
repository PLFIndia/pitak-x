/// Extracts a flat ZIP with strict size/count/zip-slip limits. Pure Dart port
/// of Kotlin `BoundedZipExtractor` (source app), itself borrowed from Signal
/// Android's BackupImporter size accounting (credited in the Kotlin source).
///
/// Why this exists (Kotlin audit F-02): a naive extractor lets a 1 KB
/// malicious archive decompress into gigabytes and wedge the device. We cap
/// each entry's decompressed size, the sum of decompressed sizes, and the
/// total entry count (see [ZipLimits]).
///
/// Zip-slip is defended two ways: names are reduced to their leaf (directory
/// components stripped) and a leaf containing `/`, `\`, or NUL is rejected. The
/// archive is intentionally flat, so directory entries / nested names are
/// refused loudly.
///
/// IMPORTANT: the ZIP's declared (central-directory) sizes are
/// attacker-supplied — we use them only as an early reject, then verify the
/// ACTUAL decompressed length against the same caps and fail closed.
///
/// KNOWN RESIDUAL (REVIEW_FINDINGS_2 S4, deferred): `archive` 3.6.1's
/// inflater pre-allocates `uncompressedSize` read from the entry's LOCAL
/// header, while our early reject uses the central-directory size. A file
/// whose two headers disagree can therefore force a large TRANSIENT
/// allocation (up to 4 GiB) before the post-decode length check fires. The
/// content is still capped; only the transient allocation is not. The proper
/// fix is the archive 4.x streaming API (allocation bounded by bytes actually
/// inflated) — tracked in PLAN.md's tier-2 dependency programme, which owns
/// the archive bump.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// True when [bytes] starts with the ZIP local-file-header magic
/// (`50 4B 03 04`, "PK\x03\x04"). Used to content-sniff a picked file as a
/// bundle vs a text export — by ImportController before decoding, and by the
/// import page's pre-read size guard, which must not apply the text cap to
/// bundles (single source of truth for the magic).
bool hasZipLocalFileHeader(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 && // 'P'
    bytes[1] == 0x4B && // 'K'
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Size/count caps for [BoundedZipExtractor.extract].
class ZipLimits {
  /// Creates limits; all values must be positive and total ≥ per-entry.
  ZipLimits({
    required this.maxEntryBytes,
    required this.maxTotalBytes,
    required this.maxEntries,
  }) : assert(maxEntryBytes > 0, 'maxEntryBytes must be positive'),
       assert(maxTotalBytes > 0, 'maxTotalBytes must be positive'),
       assert(maxEntries > 0, 'maxEntries must be positive'),
       assert(
         maxTotalBytes >= maxEntryBytes,
         'maxTotalBytes must be >= maxEntryBytes',
       );

  /// Max decompressed bytes for any single entry.
  final int maxEntryBytes;

  /// Max sum of decompressed bytes across all entries.
  final int maxTotalBytes;

  /// Max number of entries.
  final int maxEntries;

  /// Defaults for the Pitaka backup/bundle format (`PITAKA_BACKUP_LIMITS`).
  static final ZipLimits pitakaBackup = ZipLimits(
    maxEntryBytes: 200 * 1024 * 1024, // 200 MiB
    maxTotalBytes: 500 * 1024 * 1024, // 500 MiB
    maxEntries: 4096,
  );
}

/// Thrown on any limit violation or structural anomaly (zip-slip, empty name,
/// nested name, duplicate, directory entry). Distinct from IO errors so callers
/// can show "archive looks corrupt or hostile" without conflating causes.
class BoundedExtractionException implements Exception {
  /// Creates the exception with a human-readable [message].
  const BoundedExtractionException(this.message);

  /// Why extraction was rejected.
  final String message;

  @override
  String toString() => 'BoundedExtractionException: $message';
}

/// Extracts a flat ZIP into a map from sanitised leaf name to its decompressed
/// content, enforcing the configured [ZipLimits].
abstract final class BoundedZipExtractor {
  /// Decodes and validates the archive. Throws [BoundedExtractionException] on
  /// any cap violation or structural anomaly.
  static Map<String, Uint8List> extract(Uint8List bytes, {ZipLimits? limits}) {
    final caps = limits ?? ZipLimits.pitakaBackup;
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Exception catch (e) {
      throw BoundedExtractionException('Could not read ZIP: $e');
    }

    final out = <String, Uint8List>{};
    var totalBytes = 0;
    var entryCount = 0;

    for (final entry in archive) {
      entryCount++;
      if (entryCount > caps.maxEntries) {
        throw BoundedExtractionException(
          'Archive has too many entries (>${caps.maxEntries})',
        );
      }

      final rawName = entry.name;
      if (!entry.isFile) {
        throw BoundedExtractionException(
          "Archive contains a directory entry: '$rawName'",
        );
      }

      // Reduce to leaf; strip any directory component (zip-slip defence).
      final leaf = rawName.split('/').last.split(r'\').last;
      if (leaf.trim().isEmpty) {
        throw BoundedExtractionException(
          "Archive entry has an empty filename: '$rawName'",
        );
      }
      if (leaf.contains('/') ||
          leaf.contains(r'\') ||
          leaf.contains('\u0000')) {
        throw BoundedExtractionException(
          "Archive entry has an unsafe filename: '$rawName'",
        );
      }
      if (out.containsKey(leaf)) {
        throw BoundedExtractionException(
          "Archive has duplicate entry name: '$leaf'",
        );
      }

      // Early reject on the attacker-declared size before decompressing.
      if (entry.size > caps.maxEntryBytes) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' exceeds per-entry cap "
          '(${caps.maxEntryBytes} bytes)',
        );
      }

      final content = entry.content as List<int>;
      // Verify the ACTUAL decompressed length — never trust the header.
      if (content.length > caps.maxEntryBytes) {
        throw BoundedExtractionException(
          "Archive entry '$leaf' exceeds per-entry cap "
          '(${caps.maxEntryBytes} bytes)',
        );
      }
      totalBytes += content.length;
      if (totalBytes > caps.maxTotalBytes) {
        throw BoundedExtractionException(
          'Archive total exceeds cap (${caps.maxTotalBytes} bytes)',
        );
      }

      out[leaf] = Uint8List.fromList(content);
    }

    return out;
  }
}
