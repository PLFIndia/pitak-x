/// Reader for the §3.4 additive archive entries (infrastructure,
/// libNetwork.md): `identity.json` and `network.json`.
///
/// Extracted from `restore_backup.dart` to keep that file under the
/// architecture test's size ratchet — the two readers are pure functions of
/// the already-extracted zip bytes + the manifest, with no restorer state.
///
/// Both entries are ADDITIVE over a catalogue restore: announced by manifest
/// flags that default to false, validated on read, and NEVER allowed to abort
/// or roll back the restore. An invalid entry reads as "absent"; the caller
/// distinguishes absent-by-design from unreadable via the manifest flag.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';

/// The `identity.json` zip entry name (§3.4).
const String identityEntryName = 'identity.json';

/// The `network.json` zip entry name (§3.4).
const String networkEntryName = 'network.json';

/// What the §3.4 entries yielded: the validated identity and/or network rows
/// (null = absent or unreadable — see the manifest flags to tell which).
final class BackupExtras {
  /// Creates the extras snapshot.
  const BackupExtras({this.identity, this.network});

  /// The validated `identity.json` content, when present and valid.
  final BackupIdentity? identity;

  /// The validated `network.json` rows (invalid rows dropped), when the
  /// envelope parsed.
  final List<NetworkLibrary>? network;
}

/// Parses both §3.4 entries out of the extracted [files], gated on the
/// manifest flags (a false flag means absent-by-design — the entry is not
/// even looked at).
BackupExtras readBackupExtras(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  return BackupExtras(
    identity: _readIdentity(files, manifest),
    network: _readNetwork(files, manifest),
  );
}

/// The validated identity, or null when the entry is absent or invalid.
BackupIdentity? _readIdentity(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasIdentity) return null;
  final bytes = files[identityEntryName];
  if (bytes == null) return null;
  return BackupIdentity.fromJson(_utf8(bytes));
}

/// The validated rows, or null when the envelope is absent, corrupt, or
/// declares a too-new schema (fail closed: nothing is restored from it).
List<NetworkLibrary>? _readNetwork(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasNetwork) return null;
  final bytes = files[networkEntryName];
  if (bytes == null) return null;
  return NetworkArchiveCodec.decode(_utf8(bytes));
}

String _utf8(Uint8List bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
