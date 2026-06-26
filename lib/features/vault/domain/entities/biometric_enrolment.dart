/// Result of enrolling biometric vault unlock (#34 B2, AGENTS.md §6.1).
///
/// Carries the freshly generated random secret `S` (as wipeable [SecretBytes],
/// never a `String`) and `blobBio = wrap(S, MK)`. The application layer stores
/// `S` in hardware-backed storage behind a biometric gate and persists
/// `blobBio` next to the main blob. The vault key (MK) is NOT here — it never
/// leaves the Rust core. The user passphrase is never stored at all.
library;

import 'package:pitaka/core/crypto/secret_bytes.dart';

/// The (secret, blob) pair produced by `VaultRepository.wrapForBiometric`.
final class BiometricEnrolment {
  /// Creates an enrolment result. Takes ownership of [secret]; the caller must
  /// dispose it once stored.
  const BiometricEnrolment({required this.secret, required this.blobBio});

  /// The 32-byte CSPRNG secret to seal in the platform keystore (biometric-
  /// gated). Held as wipeable bytes; dispose after storing.
  final SecretBytes secret;

  /// The vault key re-wrapped under [secret]:
  /// `base64(salt).base64(iv).base64(ciphertext)`. Already ciphertext — safe to
  /// persist as a plain file (same rationale as the passphrase blob).
  final String blobBio;
}
