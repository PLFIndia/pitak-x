/// One Cloudflare asset's recorded metadata and the result of merging a
/// section into a Cloudflare snapshot (publish domain, pure Dart; Cloudflare
/// plan R5/R7).
///
/// Moved out of `cloudflare_site_manifest.dart` unchanged (publish
/// optimisation S9, plan G5: that file was at 483 of its 500 lines and
/// needed room for `coverRendition`). The manifest file re-exports both
/// types, so every import keeps working.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// One published asset's metadata.
final class CloudflareAssetEntry {
  /// Creates an entry.
  const CloudflareAssetEntry({
    required this.sha,
    required this.hash,
    required this.size,
    required this.type,
  });

  /// The host-neutral content identity (git blob sha), shared with the section
  /// merge and the snapshot digest.
  final String sha;

  /// The Cloudflare asset hash (see [CloudflareAssetHash]).
  final String hash;

  /// Byte length of the file.
  final int size;

  /// The exact content type it is served with.
  final CloudflareContentType type;

  /// Encodes this entry (public data only).
  Map<String, Object?> toJson() => {
    'sha': sha,
    'hash': hash,
    'size': size,
    'type': type.header,
  };

  /// Decodes an entry, or null when any field is missing or unknown.
  ///
  /// A wrong type is a corrupt record, not a crash: the caller treats null as
  /// "no usable entry" and re-hashes or reconciles.
  static CloudflareAssetEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sha = raw['sha'];
    final hash = raw['hash'];
    final size = raw['size'];
    final type = CloudflareContentType.forHeader(
      raw['type'] is String ? raw['type'] as String : null,
    );
    if (sha is! String || sha.isEmpty) return null;
    if (hash is! String || !CloudflareAssetHash.isValidHash(hash)) return null;
    if (size is! int || size < 0 || size > CloudflareLimits.maxFileBytes) {
      return null;
    }
    if (type == null) return null;
    return CloudflareAssetEntry(sha: sha, hash: hash, size: size, type: type);
  }

  @override
  String toString() => 'CloudflareAssetEntry($sha, $hash, $size)';
}

/// The result of merging one section into a Cloudflare snapshot.
final class CloudflareMergeResult {
  /// Creates the result.
  const CloudflareMergeResult({
    required this.files,
    required this.missingHashes,
  });

  /// The complete next Worker snapshot: path → entry.
  final Map<String, CloudflareAssetEntry> files;

  /// Paths the snapshot needs but has no trusted hash for.
  ///
  /// Non-empty means the caller must re-hash the bytes it can still read, and
  /// if any remain, stop before deploy and reconcile (R5/R23). It is never
  /// "publish without them".
  final List<String> missingHashes;
}
