/// The way to Pitak's own page of the phone's settings (core/platform,
/// review finding P4-M8, decision D131).
///
/// Why this exists (beginner note): Android shows its "Allow Pitak to take
/// pictures?" dialog twice at most. After the second "Don't allow" the
/// phone's settings are the only place where the camera can be allowed
/// again, and an app cannot change a permission itself. What it can do is
/// open the right page: Pitak's own entry in the phone's settings, from
/// which "Permissions" is one tap away.
///
/// Same seam pattern as `screen_security.dart` and `app_info.dart`: an
/// injectable interface, a channel-backed implementation, and fail-safe
/// degradation. The Android side has ONE method without an argument
/// (`AppSettingsChannel.kt`). Dart sends nothing: which page is opened is
/// decided on the Android side alone, from the app's own package name.
///
/// Where the app does not run on Android the way is "not available", and a
/// screen then does not build the button (the pattern of the document
/// picker, decision D19).
///
/// Privacy: nothing leaves the phone, no permission is needed, and nothing
/// is stored. The phone's settings app is told the app's own package name
/// and nothing else.
library;

import 'package:flutter/services.dart';
import 'package:pitaka/core/platform/app_log.dart';

/// Opens Pitak's page of the phone's settings.
abstract interface class AppSettingsOpener {
  /// Whether this platform has such a way at all. A screen builds its
  /// "Open settings" button only when this is true.
  bool get isAvailable;

  /// Opens the page. Answers whether it was opened; an implementation
  /// answers false instead of failing.
  Future<bool> open();
}

/// [AppSettingsOpener] backed by the narrow `dev.khoj.pitaka/app_settings`
/// channel (`AppSettingsChannel.kt`).
final class MethodChannelAppSettingsOpener implements AppSettingsOpener {
  /// Creates the channel-backed implementation. [onAndroid] says whether
  /// the app really runs on Android, where the other end of the channel is.
  const MethodChannelAppSettingsOpener({required bool onAndroid})
    : _onAndroid = onAndroid;

  final bool _onAndroid;

  /// The single method-channel name shared with the native side.
  static const MethodChannel _channel = MethodChannel(
    'dev.khoj.pitaka/app_settings',
  );

  @override
  bool get isAvailable => _onAndroid;

  @override
  Future<bool> open() async {
    // Not available means: nothing is tried (fail closed).
    if (!_onAndroid) return false;
    try {
      // No argument on purpose: the native side decides what it opens.
      final opened = await _channel.invokeMethod<Object?>('open');
      // What crosses the channel is untrusted (AGENTS.md §6.5): only a
      // plain `true` counts as "opened".
      return opened == true;
    } on MissingPluginException {
      // No native handler: the page was not opened.
      return false;
    } on PlatformException catch (e) {
      // A handler exists but failed. Debug builds log the error CODE only
      // (release builds log nothing). The screen keeps its sentence, which
      // says where the camera can be allowed.
      appLog('app_settings: open failed: ${e.code}');
      return false;
    }
  }
}
