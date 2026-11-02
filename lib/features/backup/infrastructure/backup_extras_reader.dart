/// Reader for the additive archive entries (infrastructure,
/// docs/ARCHITECTURE.md §5): `identity.json` and `network.json` (§3.4), the
/// ADR 0014 W2 pair `item_kinds.json` / `periodicals.json`, and the website
/// publishing record `publish_state.json` (ADR 0014 amendment, plan CV6).
///
/// Extracted from `restore_backup.dart` to keep that file under the
/// architecture test's size ratchet — the readers are pure functions of the
/// already-extracted zip bytes + the manifest, with no restorer state.
///
/// All entries are ADDITIVE over a catalogue restore: announced by manifest
/// flags that default to false, validated on read, and NEVER allowed to abort
/// or roll back the restore. An invalid entry reads as "absent"; the caller
/// distinguishes absent-by-design from unreadable via the manifest flag.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show coverEntryPrefix;
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';

/// The `manifest.json` zip entry name.
const String manifestEntryName = 'manifest.json';

/// The `identity.json` zip entry name (§3.4).
const String identityEntryName = 'identity.json';

/// The `network.json` zip entry name (§3.4).
const String networkEntryName = 'network.json';

/// The `publish_state.json` zip entry name (ADR 0014 amendment, plan CV6).
const String publishStateEntryName = 'publish_state.json';

/// Parses `manifest.json` out of the extracted [files], refusing a missing or
/// invalid manifest and a `schemaVersion` newer than this build knows (the
/// update-channel rule — fail closed before any device write).
Either<Failure, BackupManifest> parseBackupManifest(
  Map<String, Uint8List> files,
) {
  final manifestBytes = files[manifestEntryName];
  if (manifestBytes == null) {
    return left(const BackupCorruptFailure('Archive missing manifest.json'));
  }
  final manifest = BackupManifest.tryParse(_utf8(manifestBytes));
  if (manifest == null) {
    return left(const BackupCorruptFailure('Invalid manifest.json'));
  }
  if (manifest.schemaVersion > BackupManifest.knownSchemaVersion) {
    return left(SchemaTooNewFailure(manifest.schemaVersion));
  }
  return right(manifest);
}

/// What the additive entries yielded: the validated identity, network rows
/// and item-kind data (null = absent or unreadable — see the manifest flags
/// to tell which).
final class BackupExtras {
  /// Creates the extras snapshot.
  const BackupExtras({
    this.identity,
    this.network,
    this.itemKinds,
    this.periodicals,
    this.publishState,
  });

  /// The validated `identity.json` content, when present and valid.
  final BackupIdentity? identity;

  /// The validated `network.json` rows plus how many entries were dropped
  /// (invalid, duplicate, or over the codec's row cap), when the envelope
  /// parsed. Null = absent or unreadable.
  final ({List<NetworkLibrary> rows, int dropped})? network;

  /// The decoded `item_kinds.json` content (ADR 0014 W2), when present and
  /// readable. Null = absent or unreadable.
  final DecodedItemKinds? itemKinds;

  /// The decoded `periodicals.json` content (ADR 0014 W2), when present and
  /// readable. Null = absent or unreadable.
  final DecodedPeriodicals? periodicals;

  /// The validated `publish_state.json` content (plan CV6), when present and
  /// readable, with LOCAL cover sources kept only for covers this archive
  /// carries (ADR 0020 Decision 7). Null = absent or unreadable.
  final PublishStateBackup? publishState;
}

/// Parses the additive entries out of the extracted [files], gated on the
/// manifest flags (a false flag means absent-by-design — the entry is not
/// even looked at).
BackupExtras readBackupExtras(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  return BackupExtras(
    identity: _readIdentity(files, manifest),
    network: _readNetwork(files, manifest),
    itemKinds: _readItemKinds(files, manifest),
    periodicals: _readPeriodicals(files, manifest),
    publishState: _readPublishState(files, manifest),
  );
}

/// The validated identity, or null when the entry is absent, oversized, or
/// invalid (oversized ⇒ unreadable ⇒ not adopted, counted as
/// `identityInvalid` by the restore summary). The byte cap runs BEFORE UTF-8
/// decoding, so a padded entry cannot even reach the JSON parser — the same
/// "bound before parse" rule [_readNetwork] follows (review L2: the zip
/// extractor's per-entry cap is 200 MiB, sized for covers — far too much to
/// push through a JSON parse).
BackupIdentity? _readIdentity(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasIdentity) return null;
  final bytes = files[identityEntryName];
  if (bytes == null) return null;
  if (bytes.length > BackupIdentity.maxBytes) return null;
  return BackupIdentity.fromJson(_utf8(bytes));
}

/// The validated rows (+ dropped count), or null when the envelope is
/// absent, oversized, corrupt, or declares a too-new schema (fail closed:
/// nothing is restored from it). The byte cap runs BEFORE UTF-8 decoding so
/// a padded entry cannot even reach the JSON parser (review M9).
({List<NetworkLibrary> rows, int dropped})? _readNetwork(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasNetwork) return null;
  final bytes = files[networkEntryName];
  if (bytes == null) return null;
  if (bytes.length > NetworkArchiveCodec.maxBytes) return null;
  return NetworkArchiveCodec.decode(_utf8(bytes));
}

/// The decoded kinds map (+ skipped count), or null when the entry is absent,
/// oversized, or unusable (W2: bounded to 4 MiB BEFORE UTF-8 decoding, then
/// every row re-validated by the codec; rows that fail are dropped and
/// counted, the envelope itself fails closed to null).
DecodedItemKinds? _readItemKinds(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasItemKinds) return null;
  final bytes = files[itemKindsEntryName];
  if (bytes == null || bytes.length > ItemDetailsArchiveCodec.maxBytes) {
    return null;
  }
  return ItemDetailsArchiveCodec.decodeItemKinds(_utf8(bytes));
}

/// The decoded periodicals + issue entries, or null — same bound-then-parse
/// rule as [_readItemKinds].
DecodedPeriodicals? _readPeriodicals(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasPeriodicals) return null;
  final bytes = files[periodicalsEntryName];
  if (bytes == null || bytes.length > ItemDetailsArchiveCodec.maxBytes) {
    return null;
  }
  return ItemDetailsArchiveCodec.decodePeriodicals(_utf8(bytes));
}

/// The validated publishing record, or null — the same bound-then-parse rule
/// as [_readItemKinds] (16 MiB, then the codec's depth guard and its strict
/// field checks; one bad field makes the whole entry unreadable).
///
/// Its records may name the local cover file (`covers/<leaf>`) each published
/// cover came from. They are believed only for covers THIS archive carries:
/// those files are restored byte for byte next to the record that names
/// them. Any other local name — or every one, when the archive carries no
/// covers and the phone's own covers are kept — is forgotten, so the next
/// publish reads that cover again (ADR 0020 Decisions 4 and 7).
PublishStateBackup? _readPublishState(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasPublishState) return null;
  final bytes = files[publishStateEntryName];
  if (bytes == null || bytes.length > PublishStateBackupCodec.maxBytes) {
    return null;
  }
  final decoded = PublishStateBackupCodec.decode(_utf8(bytes));
  return decoded?.withLocalCoverSourcesFor(
    _carriedCoverLeaves(files, manifest),
  );
}

/// The cover file names the restore writes from this archive — the same
/// entries and the same leaf check as `buildRestoredCovers`.
Set<String> _carriedCoverLeaves(
  Map<String, Uint8List> files,
  BackupManifest manifest,
) {
  if (!manifest.hasCovers) return const {};
  return {
    for (final name in files.keys)
      if (name.startsWith(coverEntryPrefix))
        if (name.substring(coverEntryPrefix.length) case final leaf
            when CoverPaths.leafOf('${CoverPaths.prefix}$leaf') == leaf)
          leaf,
  };
}

String _utf8(Uint8List bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
