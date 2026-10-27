/// The Cloudflare static-asset content hash (publish domain, pure Dart;
/// Cloudflare plan B.7/R5).
///
/// The upload session is content-addressed: the app sends `path → {hash, size}`
/// and Cloudflare answers with the buckets of hashes it does not already have.
/// The hash is therefore the app's own key, and it must be computed exactly the
/// same way every time or the same file is re-uploaded (or, worse, a stored
/// hash stops matching the bytes).
///
/// Formula (B.7): `hex(SHA-256(base64(bytes) + extension))[0..32]` — standard
/// base64 WITH padding, the extension without its dot and with its case kept,
/// and the first 32 hex characters of the digest.
///
/// **Open question, recorded in Part M (deviation 49).** The reviewed Wrangler
/// source (`packages/deploy-helpers/src/deploy/helpers/hash.ts`) computes
/// `blake3(base64(bytes) + extension)` and slices the same 32 hex characters;
/// the Cloudflare docs only say "a 32 hexadecimal character hash of the file"
/// and name no algorithm. The plan's SHA-256 formula is implemented here
/// because (a) it is the reviewed contract, and (b) blake3 would need a new
/// runtime dependency, which R28 forbids without a product decision. The trial
/// (T4/T5) settles it: if the API rejects these hashes, the formula changes and
/// `scheme` changes with it, which invalidates stored hashes safely (R5) rather
/// than silently reusing wrong ones.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Computes Cloudflare asset hashes.
abstract final class CloudflareAssetHash {
  /// The formula this build writes, stored in the manifest as `hashScheme`.
  ///
  /// A manifest whose scheme differs is not trusted for its stored hashes: the
  /// bytes are re-hashed, and bytes that are no longer available send the
  /// publish into replacement reconciliation instead of a permanent
  /// missing-hash loop (R5).
  static const String scheme = 'sha256-b64-ext-32';

  /// Length of the hash Cloudflare accepts.
  static const int hexLength = 32;

  /// The hash of [bytes] published with [extension] (no dot, case kept).
  static String of(List<int> bytes, String extension) {
    final encoded = base64.encode(bytes);
    final digest = sha256.convert(utf8.encode('$encoded$extension'));
    return digest.toString().substring(0, hexLength);
  }

  /// The hash for [path], or null when its type is not one Pitak publishes.
  ///
  /// This is the single gate for "any other extension refuses the publish
  /// before upload" (B.7): the type allow-list decides, and the extension used
  /// in the formula is the type's canonical one.
  static String? forPath(List<int> bytes, SitePath path) {
    final type = CloudflareContentType.forPath(path);
    if (type == null) return null;
    return of(bytes, type.extension);
  }
}
