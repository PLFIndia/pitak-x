/// Content digest of one published poster (PLAN.md §3).
///
/// Why length-prefixed (beginner note): hashing `imageRef + caption` as one
/// string would make `("ab", "c")` and `("a", "bc")` collide. Writing each
/// field's length first makes the encoding unambiguous, so two different
/// posters can never share a digest by construction.
///
/// What it covers: the image *reference* and the caption text — the two
/// facts `events.json` carries. It cannot see the image bytes, so a poster
/// whose file was replaced in place under the same name is explicitly NOT
/// detected (non-goal in PLAN.md).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hex SHA-256 over the length-prefixed `(imageRef, caption)` pair.
final class PosterDigest {
  const PosterDigest._();

  /// Computes the digest. Deterministic and pure.
  static String compute({required String imageRef, required String caption}) {
    final bytes = <int>[
      ..._lengthPrefixed(imageRef),
      ..._lengthPrefixed(caption),
    ];
    return sha256.convert(bytes).toString();
  }

  /// `<byteLength>:<utf8 bytes>` — length in ASCII decimal, then a colon
  /// (which cannot appear in a decimal number), then the bytes.
  static List<int> _lengthPrefixed(String value) {
    final encoded = utf8.encode(value);
    return [...ascii.encode('${encoded.length}:'), ...encoded];
  }

  /// A stored digest is exactly 64 lowercase hex characters.
  static final RegExp _hexPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Strict gate for a digest read back from disk.
  static bool isValid(Object? value) =>
      value is String && _hexPattern.hasMatch(value);
}
