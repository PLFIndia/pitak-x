/// Salted cover-path hashing (pure domain, AGENTS.md §3.1, #32, F-01).
///
/// Port of Kotlin `PublishCoverIds`. Cover filenames in the public repo must
/// not leak the internal book id. The published cover for book id `n` is
/// `covers/<shortHex(sha256(salt||ascii(n)))>.jpg`, stable across publishes so
/// external links keep working between updates (same id maps to same path).
///
/// 16 hex chars (64 bits): across a 100k-book library the birthday-collision
/// probability is ~2.7e-10. The salt is generated once and stored encrypted; it
/// is not high-value (an attacker with disk access already has the DB), but
/// encrypting it is appropriate defence-in-depth.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Storage seam for the publish-cover salt. Production uses secure storage;
/// tests inject a fake with a known salt.
// ignore: one_member_abstracts
abstract interface class PublishCoverSaltStore {
  /// Returns the persisted salt, generating + storing it on first call.
  Future<List<int>> salt();
}

/// Computes deterministic, id-hiding cover paths.
final class PublishCoverIds {
  /// Creates the helper over [saltStore].
  const PublishCoverIds(this.saltStore);

  /// Source of the persisted salt.
  final PublishCoverSaltStore saltStore;

  /// Hex chars in the path hash (64 bits).
  static const int hashHexChars = 16;

  /// Returns the relative publish path for [bookId]'s cover, e.g.
  /// `covers/3f2c7a1b9e4d8051.jpg`.
  Future<String> pathFor(int bookId) async {
    final s = await saltStore.salt();
    return 'covers/${shortHashHex(s, bookId)}.jpg';
  }

  /// Pure helper (exposed for tests): SHA-256 of `salt || ascii(id)`, hex,
  /// first [hashHexChars] characters.
  static String shortHashHex(List<int> salt, int bookId) {
    final input = [...salt, ...ascii.encode('$bookId')];
    final digest = sha256.convert(input).toString();
    return digest.substring(0, hashHexChars);
  }
}
