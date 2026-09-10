/// Authentication-bound [BiometricKeyStore] (infrastructure, M08).
///
/// Replaces the pre-M08 store that kept the biometric secret S in
/// `flutter_secure_storage` in the clear behind a Dart boolean prompt
/// (astra-review.md M08: "code executing in the app's security context can
/// retrieve the wrapping secret without the prompt").
///
/// How it works now (Android only — M18):
///
///  1. `store(S)` → native `seal(S)`: Kotlin generates an AES-GCM key in the
///     Android Keystore with `setUserAuthenticationRequired(true)` (per-use,
///     BIOMETRIC_STRONG) and `setInvalidatedByBiometricEnrollment(true)`,
///     shows the system prompt with the cipher attached
///     (`BiometricPrompt.CryptoObject`), and only a successful prompt lets
///     Keystore run the cipher. We persist the RESULT — `{iv, ciphertext}` —
///     in `flutter_secure_storage` under a new versioned key. That record is
///     useless without the Keystore key, which never leaves the hardware.
///  2. `read()` → native `open(iv, ciphertext)`: same prompt-bound cipher in
///     decrypt mode. There is deliberately NO Dart-side path that turns the
///     stored record back into S.
///  3. A biometric re-enrolment (or a missing key) surfaces as
///     `BiometricInvalidatedFailure`; the session controller then wipes the
///     record and the biometric blob (fail closed → re-enrol with passphrase).
///
/// Legacy migration: a pre-M08 plaintext entry (`vault_biometric_secret_v1`)
/// cannot be re-sealed without a prompt at an arbitrary moment, and reading it
/// as S would keep the vulnerable path alive. It is DELETED on first contact
/// and the user re-enrols once. The old biometric blob on disk is harmless
/// without S (it is MK wrapped under a secret that no longer exists anywhere)
/// and is overwritten by the next enrolment. Documented in README/PRIVACY.
///
/// Byte hygiene (AGENTS.md §6): S crosses the channel as `Uint8List` (the
/// `StandardMethodCodec` maps it to a Kotlin `ByteArray`), via
/// `SecretBytes.useAsync` so the copy is wiped after the call. The persisted
/// record is base64 text — that is fine: it is ciphertext, not S.
///
/// Reply ownership (device-found regression, Session 13): the engine delivers
/// every platform-channel reply to Dart as a READ-ONLY view
/// (`dart:ui` `_wrapUnmodifiableByteData` → `ByteData.asUnmodifiableView()`),
/// and `StandardMessageCodec` decodes a `Uint8List` as a view over that
/// buffer. Wrapping that view in [SecretBytes] directly made `dispose()`
/// throw `UnsupportedError` — which surfaced as a Lock button that silently
/// did nothing after a biometric unlock, and an S that could never be wiped.
/// `read()` therefore copies S into memory Dart owns before wrapping it. The
/// engine's transient read-only copy cannot be wiped from Dart (it is freed
/// by GC) — the same unavoidable channel-hop residue already recorded in the
/// threat notes; Kotlin wipes its own plaintext buffer.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

/// Sealed store for the biometric secret S over the native
/// `BiometricSecretVault` channel + `flutter_secure_storage` for the record.
final class KeystoreBiometricSecretVault implements BiometricKeyStore {
  /// Creates the store. [storage] defaults to a hardened
  /// [FlutterSecureStorage]; inject a fake in tests. The native side is reached
  /// through [channel]; tests script it with `setMockMethodCallHandler`.
  KeystoreBiometricSecretVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            // Only ciphertext lives here now, but keep the record device-bound
            // and reachable only while the device is unlocked.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  /// The single method channel shared with `BiometricSecretVault.kt`.
  static const MethodChannel channel = MethodChannel(
    'dev.khoj.pitaka/biometric_secret',
  );

  /// Storage key for the sealed record `{iv, ciphertext}` (M08 layout).
  static const String recordKey = 'vault_biometric_secret_v2';

  /// Pre-M08 key that held base64(S) in the clear. Never read as S; deleted
  /// on first contact.
  static const String legacyPlaintextKey = 'vault_biometric_secret_v1';

  static const int _ivBytes = 12;

  // Error codes — the contract with the Kotlin side (kept in one place).
  static const String _codeCancelled = 'cancelled';
  static const String _codeLockout = 'lockout';
  static const String _codeInvalidated = 'invalidated';
  static const String _codeUnavailable = 'unavailable';
  static const String _codeBusy = 'busy';

  @override
  Future<Either<Failure, Unit>> store(SecretBytes secret) async {
    final Map<Object?, Object?>? sealed;
    try {
      // useAsync hands the channel a COPY and wipes it in a finally; the
      // codec serialises the bytes before this future completes.
      sealed = await secret.useAsync(
        (bytes) => channel.invokeMethod<Map<Object?, Object?>>('seal', {
          'secret': bytes,
        }),
      );
    } on PlatformException catch (e) {
      return left(_mapCode(e.code));
    } on MissingPluginException {
      return left(_noNativeHandler);
    }
    final record = _encodeRecord(sealed);
    if (record == null) {
      // Malformed native reply: never persist something we cannot open.
      await _destroyQuietly();
      return left(const CryptoFailure('biometric seal: malformed reply'));
    }
    try {
      await _storage.delete(key: legacyPlaintextKey);
      await _storage.write(key: recordKey, value: record);
      return right(unit);
    } on Exception {
      // A key without a record is useless and misleading — remove it so the
      // next enrolment starts clean (fail closed, tidy).
      await _destroyQuietly();
      return left(const StorageFailure('biometric secret store failed'));
    }
  }

  @override
  Future<Either<Failure, SecretBytes?>> read() async {
    final String? encoded;
    try {
      await _dropLegacyPlaintext();
      encoded = await _storage.read(key: recordKey);
    } on Exception {
      return left(const StorageFailure('biometric secret read failed'));
    }
    if (encoded == null) return right(null);
    final record = _decodeRecord(encoded);
    if (record == null) {
      return left(const StorageFailure('biometric secret record corrupt'));
    }
    try {
      final opened = await channel.invokeMethod<Uint8List>('open', {
        'iv': record.iv,
        'ciphertext': record.ciphertext,
      });
      if (opened == null || opened.isEmpty) {
        return left(const CryptoFailure('biometric open: empty reply'));
      }
      // `opened` is an unmodifiable view over the engine's reply buffer (see
      // the library doc). SecretBytes must own MUTABLE memory so it can wipe
      // S on dispose — copy first. `Uint8List.fromList` always allocates a
      // fresh, writable list.
      return right(SecretBytes(Uint8List.fromList(opened)));
    } on PlatformException catch (e) {
      return left(_mapCode(e.code));
    } on MissingPluginException {
      return left(_noNativeHandler);
    }
  }

  @override
  Future<bool> hasSecret() async {
    try {
      await _dropLegacyPlaintext();
      return await _storage.containsKey(key: recordKey);
    } on Exception {
      return false;
    }
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    try {
      await _storage.delete(key: legacyPlaintextKey);
      await _storage.delete(key: recordKey);
    } on Exception {
      return left(const StorageFailure('biometric secret clear failed'));
    }
    try {
      await channel.invokeMethod<void>('destroy');
    } on PlatformException {
      return left(const StorageFailure('biometric key destroy failed'));
    } on MissingPluginException {
      // No native side (non-Android/tests): nothing to destroy — the record
      // is gone, which is what "cleared" means here.
    }
    return right(unit);
  }

  // --- internals ----------------------------------------------------------

  /// Deletes the pre-M08 plaintext entry if present. Never reads its value.
  Future<void> _dropLegacyPlaintext() async {
    if (await _storage.containsKey(key: legacyPlaintextKey)) {
      await _storage.delete(key: legacyPlaintextKey);
    }
  }

  Future<void> _destroyQuietly() async {
    try {
      await channel.invokeMethod<void>('destroy');
    } on PlatformException {
      // Best-effort cleanup after an earlier failure; that failure is what
      // the caller sees.
    } on MissingPluginException {
      // No native side — nothing to destroy.
    }
  }

  /// Persisted form: `v2:<base64 iv>:<base64 ciphertext>`.
  static String? _encodeRecord(Map<Object?, Object?>? sealed) {
    if (sealed == null) return null;
    final iv = sealed['iv'];
    final ciphertext = sealed['ciphertext'];
    if (iv is! Uint8List || ciphertext is! Uint8List) return null;
    if (iv.length != _ivBytes || ciphertext.isEmpty) return null;
    return 'v2:${base64Encode(iv)}:${base64Encode(ciphertext)}';
  }

  static ({Uint8List iv, Uint8List ciphertext})? _decodeRecord(String s) {
    final parts = s.split(':');
    if (parts.length != 3 || parts[0] != 'v2') return null;
    final Uint8List iv;
    final Uint8List ciphertext;
    try {
      iv = base64Decode(parts[1]);
      ciphertext = base64Decode(parts[2]);
    } on FormatException {
      return null;
    }
    if (iv.length != _ivBytes || ciphertext.isEmpty) return null;
    return (iv: iv, ciphertext: ciphertext);
  }

  static const _noNativeHandler = ValidationFailure(
    'Biometric unlock is not available on this device.',
  );

  /// Maps the native error contract to typed failures. Messages are fixed
  /// strings — never anything the native side sent (no secret material).
  static Failure _mapCode(String code) => switch (code) {
    _codeCancelled => const ValidationFailure('Biometric unlock failed.'),
    _codeLockout => const ValidationFailure(
      'Too many attempts. Use your passphrase or try again later.',
    ),
    _codeUnavailable => const ValidationFailure(
      'Biometric unlock is not available or not set up on this device.',
    ),
    _codeBusy => const ValidationFailure(
      'Another biometric check is in progress.',
    ),
    _codeInvalidated => const BiometricInvalidatedFailure(),
    _ => const CryptoFailure('biometric keystore operation failed'),
  };
}
