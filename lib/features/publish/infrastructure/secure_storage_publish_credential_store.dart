/// flutter_secure_storage-backed [PublishCredentialStore] (infra, #32, §6.3).
///
/// The GitHub access token is a bearer secret → stored in the OS hardware-
/// backed secure store (Keystore/Keychain), exactly like the vault biometric
/// secret. The client id and target repo are not secrets but live in the same
/// store for cohesion and to avoid leaking the repo name into plain prefs.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';

/// Secure-storage implementation of the publish credential store.
final class SecureStoragePublishCredentialStore
    implements PublishCredentialStore {
  /// Creates the store. [storage] defaults to a hardened secure store; inject
  /// a fake in tests.
  SecureStoragePublishCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const String _kToken = 'gh_token';
  static const String _kClientId = 'gh_client_id';
  static const String _kRepo = 'gh_target_repo';

  Future<String?> _read(String key) async {
    final v = await _storage.read(key: key);
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Future<String?> token() => _read(_kToken);

  @override
  Future<void> setToken(String token) =>
      _storage.write(key: _kToken, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _kToken);

  @override
  Future<String?> clientId() => _read(_kClientId);

  @override
  Future<void> setClientId(String id) =>
      _storage.write(key: _kClientId, value: id);

  @override
  Future<String?> targetRepo() => _read(_kRepo);

  @override
  Future<void> setTargetRepo(String target) =>
      _storage.write(key: _kRepo, value: target);
}
