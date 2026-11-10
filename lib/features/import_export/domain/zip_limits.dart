/// Size and count caps for the bounded ZIP extractor (import/export domain,
/// ADR 0009).
///
/// In its own file since BR3: `bounded_zip_extractor.dart` is security code
/// at its line ceiling and must not grow. That file still exports this class,
/// so existing imports keep working. Nothing about the caps changed in the
/// move.
library;

import 'package:pitaka/features/backup/domain/backup_limits.dart';

/// Size/count caps for `BoundedZipExtractor.extract`.
class ZipLimits {
  /// Creates limits; all values must be positive and total ≥ per-entry.
  ///
  /// [maxArchiveBytes] defaults to `maxTotalBytes + 4 MiB`: an honest archive
  /// is never much larger than the content it is allowed to hold (deflate
  /// expands incompressible data by only a few bytes per block), so the slack
  /// only needs to cover names and directory records. A caller may set it
  /// LOWER to bound buffering more tightly than the content caps.
  /// [maxCentralDirectoryBytes] defaults to `maxEntries × 1 KiB`: a flat
  /// archive with short names needs ~50–100 bytes per record.
  ZipLimits({
    required this.maxEntryBytes,
    required this.maxTotalBytes,
    required this.maxEntries,
    int? maxArchiveBytes,
    int? maxCentralDirectoryBytes,
  }) : maxArchiveBytes = maxArchiveBytes ?? maxTotalBytes + _headerSlackBytes,
       maxCentralDirectoryBytes =
           maxCentralDirectoryBytes ?? maxEntries * _bytesPerDirectoryRecord,
       assert(maxEntryBytes > 0, 'maxEntryBytes must be positive'),
       assert(maxTotalBytes > 0, 'maxTotalBytes must be positive'),
       assert(maxEntries > 0, 'maxEntries must be positive'),
       assert(
         maxTotalBytes >= maxEntryBytes,
         'maxTotalBytes must be >= maxEntryBytes',
       ),
       assert((maxArchiveBytes ?? 1) > 0, 'maxArchiveBytes must be positive'),
       assert(
         (maxCentralDirectoryBytes ?? 1) > 0,
         'maxCentralDirectoryBytes must be positive',
       );

  /// The reader's caps for a backup with the given [limits] (BR3).
  ///
  /// Why a factory (beginner note): the backup writer checks a library
  /// against [BackupLimits] before it builds a file. Deriving the reader's
  /// caps from the same value means the two sides cannot drift apart: what
  /// the writer accepts, the reader accepts.
  ///
  /// The reader still has ONE cap for every entry, so it gets the largest of
  /// the per-kind caps.
  factory ZipLimits.forBackup(BackupLimits limits) => ZipLimits(
    maxEntryBytes: limits.largestEntryBytes,
    maxTotalBytes: limits.maxContentBytes,
    maxEntries: limits.maxEntries,
    maxArchiveBytes: limits.maxArchiveBytes,
  );

  static const int _headerSlackBytes = 4 * 1024 * 1024;
  static const int _bytesPerDirectoryRecord = 1024;

  /// Max decompressed bytes for any single entry.
  final int maxEntryBytes;

  /// Max sum of decompressed bytes across all entries.
  final int maxTotalBytes;

  /// Max number of entries.
  final int maxEntries;

  /// Max size of the compressed archive itself (the picked file). Enforced by
  /// the pickers while reading and again by the extractor.
  final int maxArchiveBytes;

  /// Max size of the ZIP central directory (all entry headers together),
  /// checked from the EOCD record before any header is parsed.
  final int maxCentralDirectoryBytes;

  /// Defaults for the Pitaka backup/bundle format (`PITAKA_BACKUP_LIMITS`):
  /// 200 MiB per entry, 500 MiB in total, 4,096 entries. Built from
  /// [BackupLimits.current], the one place that holds these numbers.
  static final ZipLimits pitakaBackup = ZipLimits.forBackup(
    BackupLimits.current,
  );
}
