/// The app's own package identity (core/platform, S35).
///
/// Why this exists (beginner note): the Play in-app update flow may run ONLY
/// in the `play` flavor (`dev.khoj.pitaka`). The F-Droid flavor
/// (`dev.khoj.pitaka.fdroid`) has no Play listing — asking Play about it
/// would be noise at best — so it must stay inert. The applicationId is the
/// one identity that differs per flavor AT RUNTIME, and only the native side
/// knows it, so a one-method [MethodChannel] exposes it.
///
/// Same seam pattern as `screen_security.dart`: an injectable interface, a
/// channel-backed implementation, and fail-safe degradation — when the
/// native side is absent (tests, desktop, iOS) the answer is `null`, which
/// callers treat as "not eligible", never as an error.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads the running app's package identity from the platform.
// ignore: one_member_abstracts
abstract interface class AppInfo {
  /// The applicationId (Android package name), or null when the platform
  /// side is unavailable or fails — "unknown" always means "not eligible"
  /// for gated features (fail safe).
  Future<String?> applicationId();
}

/// [AppInfo] backed by the narrow `dev.khoj.pitaka/app_info` channel
/// (MainActivity, S35).
final class MethodChannelAppInfo implements AppInfo {
  /// Creates the channel-backed implementation.
  const MethodChannelAppInfo();

  /// The single method-channel name shared with the native side.
  static const MethodChannel _channel = MethodChannel(
    'dev.khoj.pitaka/app_info',
  );

  @override
  Future<String?> applicationId() async {
    try {
      return await _channel.invokeMethod<String>('applicationId');
    } on MissingPluginException {
      // No native handler (non-Android/tests) — expected, means "unknown".
      return null;
    } on PlatformException catch (e) {
      // A handler exists but failed: log to the debug console only (no
      // analytics, §3) and degrade to "unknown" — identity is only ever
      // used to DISABLE a feature, never to grant one.
      debugPrint('app_info: applicationId failed: ${e.code}');
      return null;
    }
  }
}
