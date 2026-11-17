import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';

/// BR9: what an inspection hands to the notice before a restore.
void main() {
  BackupManifest manifest({
    bool hasBorrowers = false,
    bool hasBackupBlob = false,
    bool hasCovers = false,
  }) => BackupManifest(
    exportedAt: 1,
    hasBorrowers: hasBorrowers,
    hasBackupBlob: hasBackupBlob,
    hasCovers: hasCovers,
  );

  test('sizes: what a restore takes is the covers and the databases', () {
    final inspection = ArchiveInspection(
      manifest: manifest(hasCovers: true, hasBackupBlob: true),
      coverBytes: 700,
      databaseBytes: 50,
    );

    expect(inspection.sizes, (
      takenBytes: 750,
      databaseBytes: 50,
      hasCovers: true,
      hasVault: true,
    ));
  });

  test('sizes: without sizes given, nothing is taken', () {
    final inspection = ArchiveInspection(manifest: manifest());

    expect(inspection.sizes, (
      takenBytes: 0,
      databaseBytes: 0,
      hasCovers: false,
      hasVault: false,
    ));
  });

  test('sizes: "has a vault" follows the key blob, as a restore does: a '
      'vault database without its key is not restored', () {
    final withoutKey = ArchiveInspection(
      manifest: manifest(hasBorrowers: true),
    );
    final withKey = ArchiveInspection(manifest: manifest(hasBackupBlob: true));

    expect(withoutKey.sizes.hasVault, isFalse);
    expect(withKey.sizes.hasVault, isTrue);
  });
}
