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
/// **Confirmed by the S2 disposable-account trial (Part M, deviations 49/59).**
/// Cloudflare accepted this SHA-256 formula for upload sessions and bucket
/// uploads on 2026-10-27. Earlier Wrangler source used blake3, so
/// [CloudflareAssetHash.scheme] is
/// persisted with every manifest: if the formula ever changes, old hashes are
/// invalidated and rebuilt safely instead of being reused under a new meaning.
library;

import 'dart:async';
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

  /// True only for a 32-character lower-case hexadecimal asset hash.
  static bool isValidHash(String value) {
    if (value.length != hexLength) return false;
    for (final unit in value.codeUnits) {
      final digit = unit >= 0x30 && unit <= 0x39;
      final lowerHex = unit >= 0x61 && unit <= 0x66;
      if (!digit && !lowerHex) return false;
    }
    return true;
  }

  /// The hash of [bytes] published with [extension] (no dot, case kept).
  static String of(List<int> bytes, String extension) {
    final encoded = base64.encode(bytes);
    final digest = sha256.convert(utf8.encode('$encoded$extension'));
    return digest.toString().substring(0, hexLength);
  }

  /// Computes the same hash over a stream without retaining the whole file or
  /// its base64 representation.
  ///
  /// The caller supplies a bounded/reopenable stream (the bucket asset's
  /// `openValidated`). Chunk boundaries do not change the digest: the chunked
  /// base64 encoder preserves padding exactly like [of].
  static Future<String> fromStream(
    Stream<List<int>> bytes,
    String extension,
  ) async {
    final accumulator = _HashAccumulator();
    await for (final chunk in bytes) {
      accumulator.add(chunk);
    }
    return accumulator.finish(extension);
  }

  /// Passes bytes through unchanged while requiring their transmitted content
  /// to hash to [expectedHash].
  ///
  /// The check runs after the final chunk, before the stream closes. A source
  /// that changes between validation and upload (or between retries) therefore
  /// fails that attempt instead of completing under a different content hash.
  static Stream<List<int>> verifyStream({
    required Stream<List<int>> bytes,
    required String extension,
    required String expectedHash,
  }) async* {
    final accumulator = _HashAccumulator();
    await for (final chunk in bytes) {
      accumulator.add(chunk);
      yield chunk;
    }
    if (accumulator.finish(extension) != expectedHash) {
      throw const CloudflareAssetHashException();
    }
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

/// The transmitted bytes did not match the hash their upload part declared.
final class CloudflareAssetHashException implements Exception {
  /// Creates a fixed refusal with no asset bytes, path or expected hash text.
  const CloudflareAssetHashException();

  @override
  String toString() => 'CloudflareAssetHashException(content hash mismatch)';
}

/// Incremental base64-then-SHA-256 state shared by hashing and wire
/// verification.
final class _HashAccumulator {
  _HashAccumulator() {
    _shaInput = sha256.startChunkedConversion(_digestOutput);
    _base64Input = base64.encoder.startChunkedConversion(
      _EncodedHashSink(_shaInput),
    );
  }

  final _DigestValueSink _digestOutput = _DigestValueSink();
  late final ByteConversionSink _shaInput;
  late final ChunkedConversionSink<List<int>> _base64Input;

  void add(List<int> chunk) => _base64Input.add(chunk);

  String finish(String extension) {
    _base64Input.close();
    // The extension is hashed AFTER the complete padded base64 payload (B.7).
    _shaInput
      ..add(utf8.encode(extension))
      ..close();
    final digest = _digestOutput.value;
    if (digest == null) throw StateError('SHA-256 produced no digest');
    return digest.toString().substring(0, CloudflareAssetHash.hexLength);
  }
}

/// Receives encoded base64 pieces and feeds their UTF-8 bytes into SHA-256.
final class _EncodedHashSink implements Sink<String> {
  _EncodedHashSink(this._shaInput);

  final ByteConversionSink _shaInput;

  @override
  void add(String value) => _shaInput.add(utf8.encode(value));

  @override
  void close() {
    // The extension still has to be hashed after the base64 stream closes.
  }
}

/// Captures exactly one digest without depending on crypto's private helpers.
final class _DigestValueSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest value) {
    if (this.value != null) throw StateError('SHA-256 emitted two digests');
    this.value = value;
  }

  @override
  void close() {}
}
