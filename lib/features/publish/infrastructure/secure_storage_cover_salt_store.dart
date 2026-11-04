/// flutter_secure_storage-backed cover-salt store (infra, #32, F-01).
///
/// Generates a 16-byte random salt on first use and persists it (base64) in the
/// OS secure store, separate from the credential store so a "sign out" wipe
/// doesn't churn the salt and invalidate every published cover URL. The salt
/// is not a secret (plan P9): it keeps cover names and item keys stable
/// across publishes and phones and binds `availability.json` to its catalogue
/// (the key-set id); it is simply kept out of logs and `toString()`.
///
/// Every `salt()` call is one secure-storage read (about 72 ms on the test
/// phone), which is why a publish reads it ONCE (`PublishItemKeys.namingFor`,
/// plan S16) instead of once per cover.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/security/hardened_secure_storage.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// Secure-storage cover salt with lazy first-use generation.
///
/// Since plan S11 the salt can also be REPLACED, by exactly one flow: a
/// restore adopting a backup's publishing record on a phone that has not
/// published yet ([replace]; ADR 0014 amendment, plan CV7).
final class SecureStorageCoverSaltStore
    implements ReplaceablePublishCoverSaltStore {
  /// Creates the store. [storage]/[random] are injectable for tests.
  SecureStorageCoverSaltStore({FlutterSecureStorage? storage, Random? random})
    // M3 (deliberate): UNLIKE the token / biometric secret, the salt stays
    // `first_unlock_this_device`. It is NOT a secret (plan P9: the catalogue
    // is public by design; the salt exists for stable names and keys and the
    // key-set binding, not for privacy). It must also be readable in
    // background contexts (e.g. a post-reboot publish) so cover URLs stay
    // stable; the stricter accessibility would buy nothing and risk breaking
    // that.
    : _storage =
          storage ??
          hardenedSecureStorage(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  static const String _key = 'publish_cover_salt_v1';
  static const int _saltBytes = ReplaceablePublishCoverSaltStore.saltLength;

  @override
  Future<List<int>> salt() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }
    final fresh = Uint8List(_saltBytes);
    for (var i = 0; i < _saltBytes; i++) {
      fresh[i] = _random.nextInt(256);
    }
    await _storage.write(key: _key, value: base64Encode(fresh));
    return fresh;
  }

  /// Overwrites the salt with [salt] (one secure-storage write).
  ///
  /// The length is checked FIRST, so a wrong-length salt never reaches the
  /// store: every later cover path and item key is derived from it.
  @override
  Future<Either<Failure, Unit>> replace(List<int> salt) async {
    if (salt.length != _saltBytes ||
        salt.any((byte) => byte < 0 || byte > 255)) {
      return left(const ValidationFailure('Invalid publishing key'));
    }
    try {
      await _storage.write(key: _key, value: base64Encode(salt));
      return right(unit);
    } on Exception {
      // The platform error text may carry device detail; a fixed sentence is
      // all the caller needs (it rolls back and reports "not applied").
      return left(const StorageFailure('Could not save the publishing key.'));
    }
  }
}
