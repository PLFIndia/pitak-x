/// The PUBLISHED identity of a library: a fingerprint of its private ID
/// (network domain, pure Dart; docs/ARCHITECTURE.md §5.2).
///
/// The raw library ID (16–64 hex, minted from a CSPRNG) must NEVER leave the
/// device except in person or inside a JSON export the user hands over — it is
/// the namespace token every merge decision trusts. But the network feature
/// needs a stable published identity so a hub's member list and a fetched
/// descriptor can be matched against a scanned card WITHOUT publishing the ID.
///
/// The fingerprint is `SHA-256("pitak-library-fingerprint-v1:" + id)` in
/// lowercase hex. Two properties matter:
///  - **Domain separation**: the fixed prefix means this hash can never be
///    confused with any other SHA-256 of the ID computed elsewhere.
///  - **Not invertible in practice**: IDs are 128-bit random, so no dictionary
///    of candidate IDs exists to brute-force the hash against.
///
/// `package:crypto` is on the domain import allow-list (verified pure;
/// `test/architecture/domain_purity_test.dart`).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pitaka/features/library/domain/value_objects/library_id.dart';

/// Computes and validates library fingerprints (64 lowercase hex chars).
abstract final class LibraryFingerprint {
  /// Domain-separation prefix mixed into every fingerprint hash (§3.3).
  /// Part of the cross-device wire contract — changing it invalidates every
  /// published `library.json` and card QR, so it carries a version number.
  static const String domainPrefix = 'pitak-library-fingerprint-v1:';

  /// Length of a fingerprint in characters (SHA-256 = 32 bytes = 64 hex).
  static const int length = 64;

  /// The fingerprint of [libraryId], or null when the ID is not a valid
  /// Pitak library ID. Invalid IDs are refused BEFORE hashing (never hash
  /// junk): the ID first passes [LibraryId.normalizeOrNull].
  static String? of(String libraryId) {
    final id = LibraryId.normalizeOrNull(libraryId);
    if (id == null) return null;
    final digest = sha256.convert(utf8.encode('$domainPrefix$id'));
    // crypto's Digest.toString() is already lowercase hex — the wire shape.
    return digest.toString();
  }

  /// True when [value] is exactly 64 lowercase-hex characters (the shape every
  /// fingerprint on the wire must have). Rejects uppercase, short/long values,
  /// and any non-hex character.
  static bool isValid(String value) {
    if (value.length != length) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39; // 0-9
      final isLowerHex = c >= 0x61 && c <= 0x66; // a-f
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }
}
