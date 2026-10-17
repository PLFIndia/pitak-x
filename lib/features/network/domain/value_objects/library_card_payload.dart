/// The library-card QR payload (network domain, pure Dart; libNetwork.md
/// §3.2, D9 — a CROSS-DEVICE WIRE CONTRACT).
///
/// The card QR is the library's own site URL plus a fragment:
///
///     <siteUrl>#pitak-card=1&fp=<64 hex>&n=<percent-encoded name>
///
/// One QR, two readers (D9): a phone camera opens the site (the published
/// viewer never reads `location.hash` — verified for `assets/publish/
/// index.html`), and Pitak parses the fragment to adopt the library as a hub
/// member WITHOUT ever handling its raw library ID (only the fingerprint,
/// D3). Fragments are never sent to servers, so scanning leaks nothing to
/// the network.
///
/// Parse order matters (§3.2): the URL (without the fragment) is validated
/// FIRST through `BookmarkUrl.normalize`; only then is the fragment parsed.
/// A `pitaka-lib:` pairing payload is detected separately so the add-member
/// screen can say "that is a pairing code" (D2) instead of staying silent.
library;

import 'dart:convert';

import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// A validated library card: who (fingerprint + name) and where (siteUrl).
final class LibraryCard {
  // Private: the only way in is [LibraryCard.tryCreate], which validates.
  const LibraryCard._({
    required this.siteUrl,
    required this.fingerprint,
    required this.name,
  });

  /// The library's published site root URL (`BookmarkUrl`-normalized).
  final String siteUrl;

  /// The library's published fingerprint (64 lowercase hex).
  final String fingerprint;

  /// Display name (`NetworkName`-validated, trimmed 1–80).
  final String name;

  /// Builds a card, validating every part; null when any is invalid.
  static LibraryCard? tryCreate({
    required String siteUrl,
    required String fingerprint,
    required String name,
  }) {
    final url = BookmarkUrl.normalize(siteUrl);
    if (url == null) return null;
    if (!LibraryFingerprint.isValid(fingerprint)) return null;
    final normalized = NetworkName.normalizeOrNull(name);
    if (normalized == null) return null;
    return LibraryCard._(
      siteUrl: url,
      fingerprint: fingerprint,
      name: normalized,
    );
  }

  @override
  String toString() => 'LibraryCard($siteUrl)'; // name/fp stay out of logs
}

/// Encode/parse for the card QR payload (§3.2).
abstract final class LibraryCardPayload {
  /// Fragment key marking a Pitak library card, and its value: the payload
  /// version. Both are wire contract — version 1 forever means this grammar.
  static const String marker = 'pitak-card';

  /// The only payload version this build encodes and accepts.
  static const String version = '1';

  /// Total payload cap in bytes (§6): a QR the scanner can still render and
  /// a hard bound on what parse() examines.
  static const int maxPayloadBytes = 512;

  /// Encodes [card] (already validated) into the QR string.
  static String encode(LibraryCard card) {
    final name = Uri.encodeComponent(card.name);
    return '${card.siteUrl}#$marker=$version'
        '&fp=${card.fingerprint}&n=$name';
  }

  /// Parses a scanned payload into a [LibraryCard], or null when it is not a
  /// valid card (wrong shape, bad URL, bad fingerprint, bad name, over the
  /// byte cap, or a version this build does not know). NEVER throws.
  static LibraryCard? parse(String raw) {
    final trimmed = raw.trim();
    // Byte cap first (§6): bound the work before any parsing.
    if (utf8.encode(trimmed).length > maxPayloadBytes) return null;

    final hash = trimmed.indexOf('#');
    if (hash < 0) return null;
    // The URL is validated BEFORE the fragment is even looked at (§3.2).
    final siteUrl = BookmarkUrl.normalize(trimmed.substring(0, hash));
    if (siteUrl == null) return null;

    final params = _parseFragment(trimmed.substring(hash + 1));
    if (params == null) return null;
    if (params[marker] != version) return null;

    final fingerprint = params['fp'];
    if (fingerprint == null || !LibraryFingerprint.isValid(fingerprint)) {
      return null;
    }
    final name = params['n'];
    if (name == null) return null;

    return LibraryCard.tryCreate(
      siteUrl: siteUrl,
      fingerprint: fingerprint,
      name: name,
    );
  }

  /// True when [raw] is a `pitaka-lib:` PAIRING payload — the add-member
  /// screen shows a plain-words rejection for those (D2) instead of silence.
  static bool isPairingPayload(String raw) =>
      raw.trim().startsWith(LibraryQrPayload.prefix);

  /// A `%` not followed by two hex digits — `Uri.decodeComponent` would throw
  /// ArgumentError on it, so malformed payloads are refused BEFORE decoding
  /// (repo rule: never catch Error subclasses as control flow).
  static final RegExp _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// Splits `k=v&k=v` with percent-decoding; null on malformed input
  /// (a bad % escape or invalid UTF-8). Pairs without `=` are skipped and
  /// unknown keys are kept but ignored by the caller (§3.2 additive
  /// evolution).
  static Map<String, String>? _parseFragment(String fragment) {
    final out = <String, String>{};
    for (final pair in fragment.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue; // not a k=v pair — ignore it
      final key = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (_badEscape.hasMatch(value)) return null;
      try {
        out[key] = Uri.decodeComponent(value);
      } on FormatException {
        return null; // percent bytes that are not valid UTF-8
      }
    }
    return out.isEmpty ? null : out;
  }
}
