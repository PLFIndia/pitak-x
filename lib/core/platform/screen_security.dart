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

import 'package:flutter/services.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// Pure policy: the window must be screen-capture-protected exactly when the
/// vault is unlocked (vault PII is on screen). Mirrors Kotlin
/// `VaultWindowSecurity.shouldSecure`.
bool shouldSecureForState(VaultSessionState state) => state is VaultUnlocked;

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
/// Android maps this to `WindowManager.LayoutParams.FLAG_SECURE`. Other
/// platforms have no handler registered; a [MissingPluginException] is caught
/// and treated as a no-op (the feature simply has no effect there).
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
      // No native handler on this platform (iOS/desktop/tests) — no-op.
    } on PlatformException {
      // Never let a window-flag failure crash a vault flow; fail open visually
      // but the data itself is already protected by encryption at rest.
    }
  }
}
