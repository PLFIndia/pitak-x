/// flutter_secure_storage-backed [PublishCredentialStore] (infra, #32, §6.3).
///
/// The GitHub access token is a bearer secret → stored in the OS hardware-
/// backed secure store (Keystore/Keychain), exactly like the vault biometric
/// secret. The target repo is not a secret but lives in the same store for
/// cohesion and to avoid leaking the repo name into plain prefs.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pitaka/core/security/hardened_secure_storage.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';

/// Secure-storage implementation of the publish credential store.
final class SecureStoragePublishCredentialStore
    implements PublishCredentialStore {
  /// Creates the store. [storage] defaults to a hardened secure store; inject
  /// a fake in tests.
  SecureStoragePublishCredentialStore({FlutterSecureStorage? storage})
    // M3: the GitHub token is a bearer secret, so the default
    // `unlocked_this_device` accessibility applies: readable ONLY while the
    // device is unlocked (not merely "unlocked once since boot"), and never
    // migrating to another device (AGENTS §6.3; see the factory).
    : _storage = storage ?? hardenedSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kToken = 'gh_token';
  static const String _kRepo = 'gh_target_repo';

  /// Key under which older builds stored a user-supplied OAuth client id.
  /// The id is baked into the app now (`github_oauth_app.dart`), so the
  /// stored copy is stale — deleted opportunistically (data minimization).
  static const String _kLegacyClientId = 'gh_client_id';

  Future<String?> _read(String key) async {
    final v = await _storage.read(key: key);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// One-shot flag so the legacy cleanup runs at most once per app session.
  bool _legacyCleaned = false;

  Future<void> _cleanLegacy() async {
    if (_legacyCleaned) return;
    _legacyCleaned = true;
    // Deleting a non-existent key is a no-op — safe and idempotent.
    await _storage.delete(key: _kLegacyClientId);
  }

  @override
  Future<String?> token() async {
    await _cleanLegacy();
    return _read(_kToken);
  }

  @override
  Future<void> setToken(String token) =>
      _storage.write(key: _kToken, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _kToken);

  @override
  Future<String?> targetRepo() => _read(_kRepo);

  @override
  Future<void> setTargetRepo(String target) =>
      _storage.write(key: _kRepo, value: target);

  @override
  Future<void> clearTargetRepo() => _storage.delete(key: _kRepo);
}
