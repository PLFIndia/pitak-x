/// Domain ports for biometric vault unlock (#34 B2, AGENTS.md §3.1/§3.3).
///
/// Two narrow interfaces, declared in `domain` and implemented in
/// `infrastructure`, keep the application layer free of platform plugins:
///
///  - [BiometricAuthenticator] — the device biometric/credential GATE. It only
///    proves "a live user authenticated"; it never sees the vault key or the
///    stored secret. Mirrors the Kotlin app's F-06 software gate (a successful
///    prompt is the capability that authorizes releasing the secret), NOT an
///    auth-bound hardware key (which the Kotlin audit reverted as fragile).
///
///  - [BiometricKeyStore] — hardware-backed storage (Keystore/Keychain) for the
///    random secret `S`. `S` is the only thing persisted for biometric unlock;
///    the user passphrase is never stored, and the vault key never leaves Rust.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';

/// Whether biometric unlock can be offered, and the result of a prompt.
enum BiometricAvailability {
  /// Hardware present and at least one biometric/credential enrolled.
  available,

  /// Hardware present but nothing enrolled by the user yet.
  notEnrolled,

  /// No biometric hardware / platform support (e.g. desktop, emulator).
  unavailable,
}

/// Can the device authenticate the user AT ALL (biometric OR PIN/pattern)?
///
/// Distinct from [BiometricAvailability], which is about *biometrics*: the app
/// lock accepts the device credential as a fallback, so it only becomes
/// impossible to pass when the device has NO screen lock configured. That is
/// the case the launch gate must recover from (review 2026-09-03, decision
/// Q5): with no credential to check, every prompt fails and the user would be
/// locked out of their own library forever.
enum DeviceCredentialStatus {
  /// A biometric or a device PIN/pattern/password can be checked.
  available,

  /// The device has no screen lock and no biometric — authentication can
  /// never succeed until the user sets one up in system settings.
  noneConfigured,

  /// Platform gives no answer (plugin error); treat as unknown, keep locked.
  unknown,
}

/// The device biometric/credential gate. Implemented over `local_auth`.
abstract interface class BiometricAuthenticator {
  /// Reports whether biometric unlock can be offered on this device.
  Future<BiometricAvailability> availability();

  /// Prompts the user to authenticate with [reason] shown in the system
  /// dialog. Returns `true` only on a successful live authentication; `false`
  /// on cancel/failure. Never throws to the caller (errors map to `false`).
  Future<bool> authenticate({required String reason});

  /// Whether the device can authenticate the user by ANY means (see
  /// [DeviceCredentialStatus]). Never throws.
  Future<DeviceCredentialStatus> deviceCredentialStatus();
}

/// Hardware-backed storage for the biometric secret `S`. Implemented over
/// `flutter_secure_storage` (Keystore/Keychain).
///
/// `S` is handled as wipeable [SecretBytes] in memory; at rest it lives only in
/// the OS secure store. Returns `Either<Failure, T>`; never throws across the
/// layer.
abstract interface class BiometricKeyStore {
  /// Persists [secret] in the platform secure store. Takes a defensive copy;
  /// the caller still owns and disposes [secret].
  Future<Either<Failure, Unit>> store(SecretBytes secret);

  /// Reads the stored secret, or `null` (right) when none is enrolled. The
  /// caller owns the returned [SecretBytes] and must dispose it.
  Future<Either<Failure, SecretBytes?>> read();

  /// True when a secret is currently stored (biometric unlock is enrolled).
  Future<bool> hasSecret();

  /// Deletes the stored secret (disable biometric unlock / wipe). Idempotent.
  Future<Either<Failure, Unit>> clear();
}
