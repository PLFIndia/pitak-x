/// Screen-capture protection for vault (PII-bearing) screens (§2a.6, #34/F-12).
///
/// When the vault is unlocked, borrower names and loan lists render on screen.
/// Without protection the Android Recents/Overview thumbnail captures that PII
/// and screen-cast / accessibility services can read the pixels. The fix is to
/// set Android `FLAG_SECURE` while the vault is unlocked and clear it when
/// locked — mirroring the Kotlin source app's `VaultWindowSecurity` + the
/// `MainActivity` window-flag toggle.
///
/// The decision (`shouldSecure`) is a pure function so it is unit-tested; the
/// actual platform call crosses a narrow [MethodChannel] (no new dependency —
/// keeps the native surface minimal). On platforms without an implementation
/// (iOS, desktop, tests) the call degrades to a silent no-op.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// Pure policy: the window must be screen-capture-protected when the vault is
/// unlocked (vault PII is on screen) — mirroring Kotlin
/// `VaultWindowSecurity.shouldSecure` — OR while any passphrase entry field
/// is visible (REVIEW_FINDINGS_2 S2: the create/unlock/change/restore flows
/// run BEFORE any unlock succeeds, so keying off `VaultUnlocked` alone left
/// those screens capturable).
bool shouldSecureForState(
  VaultSessionState state, {
  bool passphraseEntryVisible = false,
}) => state is VaultUnlocked || passphraseEntryVisible;

/// Toggles OS-level screen-capture protection for the app window.
///
/// Kept as an interface (not a single function) so it can be injected /
/// overridden in tests via Riverpod, matching the repo's repository style.
// ignore: one_member_abstracts
abstract interface class ScreenSecurity {
  /// Enables (`secure == true`) or disables screen-capture protection.
  Future<void> setSecure({required bool secure});
}

/// [ScreenSecurity] backed by a narrow platform [MethodChannel].
///
/// PLATFORM MATRIX (M18, astra-review.md): Android is the only shipping
/// target. Android maps this to `WindowManager.LayoutParams.FLAG_SECURE`
/// (MainActivity). Other platforms register no handler; that case is a
/// deliberate no-op, and the README states plainly that capture protection
/// exists only on Android.
final class MethodChannelScreenSecurity implements ScreenSecurity {
  /// Creates the channel-backed implementation.
  const MethodChannelScreenSecurity();

  /// The single method-channel name shared with the native side.
  static const MethodChannel _channel = MethodChannel(
    'dev.khoj.pitaka/screen_security',
  );

  @override
  Future<void> setSecure({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // No native handler on this platform (non-Android/tests) — an expected
      // no-op, not a failure.
    } on PlatformException catch (e) {
      // M18: a handler EXISTS but failed (Android) — that is a real defect
      // in the capture shield, so it must not be silent. Log it (debug
      // console only — no analytics, no PII, §3), but never crash a vault
      // flow: the data itself is still protected by encryption at rest.
      debugPrint('screen_security: setSecure($secure) failed: ${e.code}');
    }
  }
}
