/// What a picked archive carries, without restoring it (backup domain,
/// docs/ARCHITECTURE.md §5.5).
///
/// `inspectArchive` used to return the bare [BackupManifest]; the restore
/// page's copy needs one more fact — the NAME inside `identity.json` ("This
/// backup carries the library identity for '<name>'; restoring adopts it.").
/// The manifest only has the `hasIdentity` flag, so inspection now also
/// parses the identity entry (cheap, already-extracted bytes) and surfaces
/// the validated identity when there is one.
library;

import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';

/// Bounded, read-only look inside a `.pitabak` archive.
final class ArchiveInspection {
  /// Creates an inspection result.
  const ArchiveInspection({
    required this.manifest,
    this.identity,
    this.publishState,
    this.coverBytes = 0,
    this.databaseBytes = 0,
  }) : assert(coverBytes >= 0, 'coverBytes must not be negative'),
       assert(databaseBytes >= 0, 'databaseBytes must not be negative');

  /// The parsed manifest (what the archive declares).
  final BackupManifest manifest;

  /// The validated identity from `identity.json` when the archive carries a
  /// USABLE one — null when the entry is absent OR invalid (the page then
  /// falls back to a name-less sentence keyed off `manifest.hasIdentity`).
  final BackupIdentity? identity;

  /// The validated website publishing record (plan CV6) when the archive
  /// carries a USABLE one, so the page can name its site — null when absent
  /// OR unreadable (the page then keys off `manifest.hasPublishState`).
  final PublishStateBackup? publishState;

  /// How many bytes a restore writes for the cover pictures of this
  /// archive, as its directory declares them (backup rework BR9). The
  /// reader has already held every one of them to the limits of a backup.
  final int coverBytes;

  /// The same for the databases a restore unpacks (books, wishlist, and
  /// the borrowers vault when the archive carries one).
  final int databaseBytes;

  /// What the notice before a restore needs to know about this archive
  /// (see `restoreStorageNeedBytes`).
  RestoreArchiveSizes get sizes => (
    takenBytes: coverBytes + databaseBytes,
    databaseBytes: databaseBytes,
    hasCovers: manifest.hasCovers,
    hasVault: manifest.hasBackupBlob,
  );
}
