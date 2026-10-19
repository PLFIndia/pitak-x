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

/// Bounded, read-only look inside a `.pitabak` archive.
final class ArchiveInspection {
  /// Creates an inspection result.
  const ArchiveInspection({required this.manifest, this.identity});

  /// The parsed manifest (what the archive declares).
  final BackupManifest manifest;

  /// The validated identity from `identity.json` when the archive carries a
  /// USABLE one — null when the entry is absent OR invalid (the page then
  /// falls back to a name-less sentence keyed off `manifest.hasIdentity`).
  final BackupIdentity? identity;
}
