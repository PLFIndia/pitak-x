import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';

/// BR3: the reader's caps for a backup are built from `BackupLimits`. The
/// numbers below are what the released app (1.9.7) enforces; a change here
/// changes which backups can be restored.
void main() {
  const mebibyte = 1024 * 1024;

  test("ZipLimits.pitakaBackup still holds the released reader's numbers", () {
    final limits = ZipLimits.pitakaBackup;
    expect(limits.maxEntries, 4096);
    expect(limits.maxTotalBytes, 500 * mebibyte);
    expect(limits.maxEntryBytes, 200 * mebibyte);
    // The two derived caps, as the old defaults computed them: content plus
    // 4 MiB, and 1 KiB of directory per entry.
    expect(limits.maxArchiveBytes, 504 * mebibyte);
    expect(limits.maxCentralDirectoryBytes, 4096 * 1024);
  });

  test('pitakaBackup is BackupLimits.current, not a second set of numbers', () {
    final limits = ZipLimits.pitakaBackup;
    const backup = BackupLimits.current;
    expect(limits.maxEntries, backup.maxEntries);
    expect(limits.maxTotalBytes, backup.maxContentBytes);
    expect(limits.maxEntryBytes, backup.largestEntryBytes);
    expect(limits.maxArchiveBytes, backup.maxArchiveBytes);
  });

  test('forBackup follows the limits it is given', () {
    final limits = ZipLimits.forBackup(
      const BackupLimits(
        maxCovers: 5,
        maxContentBytes: 9000,
        maxCoverBytes: 100,
        maxDatabaseBytes: 8000,
        maxTextEntryBytes: 300,
        archiveOverheadBytes: 700,
      ),
    );
    expect(limits.maxEntries, 15);
    expect(limits.maxTotalBytes, 9000);
    expect(limits.maxEntryBytes, 8000);
    expect(limits.maxArchiveBytes, 9700);
    expect(limits.maxCentralDirectoryBytes, 15 * 1024);
  });
}
