/// flutter_secure_storage-backed [LookupKeyStore] (infrastructure, §6.3).
///
/// Same hardening profile as the publish credential store: encrypted prefs
/// on Android, Keychain `unlocked_this_device` on iOS (readable only while
/// unlocked; never migrates to another device via backup).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pitaka/core/security/hardened_secure_storage.dart';
import 'package:pitaka/features/lookup/domain/lookup_key_store.dart';

/// Secure-storage implementation of [LookupKeyStore].
final class SecureStorageLookupKeyStore implements LookupKeyStore {
  /// Creates the store. [storage] defaults to the hardened secure store;
  /// inject a fake in tests.
  SecureStorageLookupKeyStore({FlutterSecureStorage? storage})
    // The lookup API key is a bearer credential: device-unlocked only.
    : _storage = storage ?? hardenedSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kGoogleKey = 'google_books_api_key';

  @override
  Future<String?> googleBooksApiKey() async {
    final v = await _storage.read(key: _kGoogleKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Future<void> setGoogleBooksApiKey(String key) =>
      _storage.write(key: _kGoogleKey, value: key);

  @override
  Future<void> clearGoogleBooksApiKey() => _storage.delete(key: _kGoogleKey);
}
