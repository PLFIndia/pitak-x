/// Salted cover-path hashing (pure domain, AGENTS.md §3.1, #32, F-01).
///
/// Port of Kotlin `PublishCoverIds`. The published cover for book id `n` is
/// `covers/<shortHex(sha256(salt||utf8(n)))>.jpg`, stable across publishes so
/// external links keep working between updates (same id maps to same path).
///
/// Why a salt at all (plan P9, 2026-11-04): the catalogue is public by design
/// (P8), so hiding row numbers is not the point. The salt stays because
/// (1) cover names and item keys stay stable across publishes and across
/// phones through backups, and (2) the key-set id derived from it binds
/// `availability.json` to the catalogue it was made for (plan J10). It is
/// public-safe data: never logged, never in `toString()`, nothing more.
///
/// 16 hex chars (64 bits): across a 100k-book library the birthday-collision
/// probability is ~2.7e-10.
///
/// Since plan S16 (D.5) this file holds the salt store port and the pure hash
/// helpers only. The names of one publish are computed by `PublishCoverNames`
/// from ONE salt read; nothing here reads the store.
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

/// The pure salted-hash helpers behind cover names and item keys.
///
/// Static only, on purpose: the ONE place the hash input is spelled out, so a
/// cover name (`PublishCoverNames`) and an item key (`PublishItemKeys`) can
/// never drift from the bytes that are already online.
abstract final class PublishCoverIds {
  /// Hex chars in the path hash (64 bits).
  static const int hashHexChars = 16;

  /// Pure helper: SHA-256 of `salt || utf8(id)`, hex, first [hashHexChars]
  /// characters. Decimal ASCII ids keep their old bytes.
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
