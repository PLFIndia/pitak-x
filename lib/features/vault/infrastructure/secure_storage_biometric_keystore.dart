/// flutter_secure_storage-backed [BiometricKeyStore] (infrastructure, #34 B2).
///
/// Stores the biometric secret S in the OS hardware-backed secure store
/// (Android Keystore-wrapped, iOS Keychain). S is the ONLY thing persisted for
/// biometric unlock; the user passphrase is never stored and the vault key (MK)
/// never leaves the Rust core.
///
/// At-rest encoding: S (raw bytes) is base64-encoded for the String-typed
/// secure-storage API, then immediately decoded back to wipeable bytes on
/// read. The transient base64 String is the unavoidable boundary cost (the
/// plugin API is String-only) and cannot be wiped from the GC heap — an
/// ACCEPTED, documented §6.6 exception until a byte-capable secure-storage
/// channel exists. Everything this file CAN control is wipeable: no decoded
/// byte buffer is ever left un-owned (the `SecretBytes` returned by `read()`
/// takes ownership of the decoder's buffer directly — zero intermediates).
library;

import 'dart:convert';

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
            // M3: the biometric secret S gates vault (borrower PII) unlock.
            // `unlocked_this_device` keeps it readable ONLY while the device is
            // unlocked, and non-migrating across devices — a stolen, locked
            // phone never exposes S even after a reboot-and-first-unlock by an
            // attacker who lacks the screen lock.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
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
      // base64Decode returns a FRESH Uint8List; hand it straight to
      // SecretBytes, which takes ownership and wipes it on dispose. Copying
      // here would strand an un-wipeable duplicate of S on the heap (§6.1).
      return right(SecretBytes(base64Decode(encoded)));
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
