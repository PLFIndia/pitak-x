/// `local_auth`-backed [BiometricAuthenticator] (infrastructure, #34 B2).
///
/// Thin adapter over the official `local_auth` plugin. It is purely a GATE: a
/// successful prompt is the capability that authorizes releasing the stored
/// secret S (the Kotlin F-06 software-gate model). It never sees the vault key
/// or S. All plugin exceptions degrade to a safe negative result — failing
/// closed (no authentication) rather than throwing into the vault flow.
library;

import 'package:local_auth/local_auth.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

/// Biometric gate implemented with `local_auth`.
final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  /// Creates the authenticator. [auth] defaults to a real
  /// [LocalAuthentication]; inject a fake in tests.
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricAvailability.unavailable;
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      if (!canCheck && enrolled.isEmpty) {
        // Device supports credential fallback but no biometrics enrolled.
        return BiometricAvailability.notEnrolled;
      }
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Exception {
      return BiometricAvailability.unavailable;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // stickyAuth survives app backgrounding mid-prompt; the default
        // (biometricOnly: false) allows device PIN/pattern fallback.
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on Exception {
      // Any plugin error → treat as not authenticated (fail closed).
      return false;
    }
  }
}
