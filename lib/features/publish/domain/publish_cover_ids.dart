/// Salted cover-path hashing (pure domain, AGENTS.md §3.1, #32, F-01).
///
/// Port of Kotlin `PublishCoverIds`. Cover filenames in the public repo must
/// not leak the internal book id. The published cover for book id `n` is
/// `covers/<shortHex(sha256(salt||utf8(n)))>.jpg`, stable across publishes so
/// external links keep working between updates (same id maps to same path).
///
/// 16 hex chars (64 bits): across a 100k-book library the birthday-collision
/// probability is ~2.7e-10. The salt is generated once and stored encrypted; it
/// is not high-value (an attacker with disk access already has the DB), but
/// encrypting it is appropriate defence-in-depth.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Storage seam for the publish-cover salt. Production uses secure storage;
/// tests inject a fake with a known salt.
// ignore: one_member_abstracts
abstract interface class PublishCoverSaltStore {
  /// Returns the persisted salt, generating + storing it on first call.
  Future<List<int>> salt();
}

/// The salt store that may also REPLACE the salt (plan CV7, S11).
///
/// A separate, narrower port on purpose (beginner note): every publish only
/// needs to READ the salt, so only the one flow that may change it — adopting
/// a backup's publishing record on a phone that has not published yet
/// (`RestoredPublishStateAdopter`) — gets this type. Replacing the salt
/// renames every cover and changes every public item key, so that flow must
/// also clear `catalogueKeyed` in both records (ADR 0019 Decision 3);
/// `test/architecture/publish_salt_invariant_test.dart` pins both facts.
// ignore: one_member_abstracts
abstract interface class ReplaceablePublishCoverSaltStore
    implements PublishCoverSaltStore {
  /// The length every salt has (16 random bytes).
  static const int saltLength = 16;

  /// Stores [salt] in place of the current one. A salt of any other length
  /// than [saltLength] is refused (`ValidationFailure`) and nothing is
  /// written; a platform failure is a `StorageFailure`.
  Future<Either<Failure, Unit>> replace(List<int> salt);
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

  /// Returns the relative publish path for a PERIODICAL's cover (ADR 0014
  /// W4: series covers go through the same salted pipeline as book covers).
  /// Keyed on the stable `periodicalUid` — not the per-device id — so a
  /// reinstall keeps linking to the same published file, and the
  /// `periodical:` prefix keeps the hash domain separate from [pathFor]
  /// (a periodical can never collide with a book's cover path).
  Future<String> pathForPeriodical(String periodicalUid) async {
    final s = await saltStore.salt();
    return 'covers/${shortHashHexForKey(s, 'periodical:$periodicalUid')}.jpg';
  }

  /// Pure helper (exposed for tests): SHA-256 of `salt || utf8(id)`, hex,
  /// first [hashHexChars] characters. Decimal ASCII ids keep their old bytes.
  static String shortHashHex(List<int> salt, int bookId) =>
      shortHashHexForKey(salt, '$bookId');

  /// Pure helper: SHA-256 of `salt || utf8(key)`, hex, first
  /// [hashHexChars] characters. UTF-8 accepts every canonical external UID;
  /// ASCII keys remain byte-for-byte compatible with the old hash input.
  static String shortHashHexForKey(List<int> salt, String key) {
    final input = [...salt, ...utf8.encode(key)];
    final digest = sha256.convert(input).toString();
    return digest.substring(0, hashHexChars);
  }
}
