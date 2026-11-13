/// Size and count caps for the app's ZIP reader (import/export domain,
/// ADR 0009).
///
/// Plain numbers, so they live in the domain layer: the rules that judge an
/// archive (`zip_entry_rules.dart`) need them, and so does the backup
/// writer, which must not build what the reader would refuse.
library;

import 'package:pitaka/features/backup/domain/backup_limits.dart';

/// Size/count caps for reading one ZIP archive (`BoundedZipFile.open`).
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
  /// [maxEntryBytes] gets the largest of the per-kind caps. It is what an
  /// entry is held to when the caller gives no rule for its name; a
  /// restore gives one for every name (`backupEntryRule`).
  factory ZipLimits.forBackup(BackupLimits limits) => ZipLimits(
    maxEntryBytes: limits.largestEntryBytes,
    maxTotalBytes: limits.maxContentBytes,
    maxEntries: limits.maxEntries,
    maxArchiveBytes: limits.maxArchiveBytes,
  );

  static const int _headerSlackBytes = 4 * 1024 * 1024;
  static const int _bytesPerDirectoryRecord = 1024;

  /// Max decompressed bytes for a single entry that has no rule of its own
  /// (see `ZipEntryPolicy`): the reader was opened without a policy.
  final int maxEntryBytes;

  /// Max sum of decompressed bytes across all entries.
  final int maxTotalBytes;

  /// Max number of entries.
  final int maxEntries;

  /// Max size of the compressed archive itself (the picked file). Enforced
  /// while the picked file is copied and again by the reader.
  final int maxArchiveBytes;

  /// Max size of the ZIP central directory (all entry headers together),
  /// checked from the EOCD record before any header is parsed.
  final int maxCentralDirectoryBytes;

  /// Defaults for the Pitaka backup format (`PITAKA_BACKUP_LIMITS`):
  /// 200 MiB per entry, 500 MiB in total, 4,096 entries. Built from
  /// [BackupLimits.current], the one place that holds these numbers.
  static final ZipLimits pitakaBackup = ZipLimits.forBackup(
    BackupLimits.current,
  );
}
