/// flutter_secure_storage-backed [BiometricKeyStore] (infrastructure, #34 B2).
///
/// Stores the biometric secret S in the OS hardware-backed secure store
/// (Android Keystore-wrapped, iOS Keychain). S is the ONLY thing persisted for
/// biometric unlock; the user passphrase is never stored and the vault key (MK)
/// never leaves the Rust core.
///
/// At-rest encoding: S (raw bytes) is base64-encoded for the String-typed
/// secure-storage API, then immediately decoded back to wipeable bytes on read.
/// The transient base64 String is the unavoidable boundary cost (the plugin
/// API is String-only); it is not retained.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

/// Hardware-backed store for the biometric secret S.
final class SecureStorageBiometricKeyStore implements BiometricKeyStore {
  /// Creates the store. [storage] defaults to a hardened
  /// [FlutterSecureStorage]; inject a fake in tests.
  SecureStorageBiometricKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// Storage key for the biometric secret.
  static const String _key = 'vault_biometric_secret_v1';

  @override
  Future<Either<Failure, Unit>> store(SecretBytes secret) async {
    try {
      final encoded = secret.use(base64Encode);
      await _storage.write(key: _key, value: encoded);
      return right(unit);
    } on Exception catch (e) {
      return left(StorageFailure('biometric secret store: $e'));
    }
  }

  @override
  Future<Either<Failure, SecretBytes?>> read() async {
    try {
      final encoded = await _storage.read(key: _key);
      if (encoded == null) return right(null);
      final bytes = base64Decode(encoded);
      return right(SecretBytes(Uint8List.fromList(bytes)));
    } on Exception catch (e) {
      return left(StorageFailure('biometric secret read: $e'));
    }
  }

  @override
  Future<bool> hasSecret() async {
    try {
      return await _storage.containsKey(key: _key);
    } on Exception {
      return false;
    }
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    try {
      await _storage.delete(key: _key);
      return right(unit);
    } on Exception catch (e) {
      return left(StorageFailure('biometric secret clear: $e'));
    }
  }
}
