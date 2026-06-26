/// flutter_secure_storage-backed cover-salt store (infra, #32, F-01).
///
/// Generates a 16-byte random salt on first use and persists it (base64) in the
/// OS secure store, separate from the credential store so a "sign out" wipe
/// doesn't churn the salt and invalidate every published cover URL. Defence-in-
/// depth: the salt only hides enumerable internal ids on the public page; an
/// attacker with disk access already has the DB.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// Secure-storage cover salt with lazy first-use generation.
final class SecureStorageCoverSaltStore implements PublishCoverSaltStore {
  /// Creates the store. [storage]/[random] are injectable for tests.
  SecureStorageCoverSaltStore({FlutterSecureStorage? storage, Random? random})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          ),
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  static const String _key = 'publish_cover_salt_v1';
  static const int _saltBytes = 16;

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
}
