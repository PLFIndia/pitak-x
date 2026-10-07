/// Play-backed [AppUpdateService] (infrastructure, S35; own channel S36).
///
/// Side effects live here (AGENTS.md §3.1): the `dev.khoj.pitaka/app_update`
/// method + event channels (our own Kotlin in `android/app/src/play`, see
/// `AppUpdateChannel.kt`) and the platform identity probe. Every expected
/// platform failure — no Play Store, a non-Play install, a refused or failed
/// download, NO NATIVE HANDLER AT ALL (the fdroid flavor registers none) —
/// degrades to the safe negative, so the feature can only ever go silent,
/// never break the app.
///
/// Why our own channel instead of the `in_app_update` plugin (beginner
/// note): a Flutter plugin's native code is linked into every flavor, and
/// that plugin bundles Google's proprietary Play Core library — unacceptable
/// in the F-Droid build. Plain per-flavor Kotlin can be excluded; a plugin
/// cannot. The Dart contract (this class, the port, the controller) is the
/// same as before.
///
/// Only the FLEXIBLE flow is wired (decision D2: background download, never
/// blocking).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';

/// Play's `UpdateAvailability` integer codes (Android reference:
/// `com.google.android.play.core.install.model.UpdateAvailability`).
/// Kept as named constants, not an enum, because they arrive as raw ints
/// over the channel and any OTHER value must be treated as "unknown".
abstract final class PlayUpdateAvailability {
  /// Play could not determine availability.
  static const int unknown = 0;

  /// No update is available.
  static const int updateNotAvailable = 1;

  /// An update is available.
  static const int updateAvailable = 2;

  /// A download started by this app is already running / finished.
  static const int developerTriggeredUpdateInProgress = 3;
}

/// Play's `InstallStatus` integer codes (Android reference:
/// `com.google.android.play.core.install.model.InstallStatus`).
abstract final class PlayInstallStatus {
  /// No install state known.
  static const int unknown = 0;

  /// Download queued.
  static const int pending = 1;

  /// Download running.
  static const int downloading = 2;

  /// Play is installing the downloaded update.
  static const int installing = 3;

  /// The update is installed (fires after the restart).
  static const int installed = 4;

  /// The download/install failed.
  static const int failed = 5;

  /// The user canceled the download.
  static const int canceled = 6;

  /// Download complete; `completeUpdate` may be called.
  static const int downloaded = 11;
}

/// The minimal, validated reply to `checkForUpdate` (a Value Object of the
/// channel boundary): the three facts the flow decides on, nothing else.
@immutable
final class PlayUpdateCheck {
  /// Creates a validated reply.
  const PlayUpdateCheck({
    required this.updateAvailability,
    required this.flexibleAllowed,
    required this.installStatus,
  });

  /// Parses the raw channel map. Returns null for ANY malformed input
  /// (missing key, wrong type) — the caller treats null as "no update"
  /// (fail closed to silence). Codes outside Play's documented set are kept
  /// as-is and fall into the `unknown` branches of the mappings.
  static PlayUpdateCheck? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final availability = raw['updateAvailability'];
    final flexible = raw['flexibleAllowed'];
    final status = raw['installStatus'];
    if (availability is! int || flexible is! bool || status is! int) {
      return null;
    }
    return PlayUpdateCheck(
      updateAvailability: availability,
      flexibleAllowed: flexible,
      installStatus: status,
    );
  }

  /// One of [PlayUpdateAvailability].
  final int updateAvailability;

  /// Whether Play allows the flexible (background) flow for this update.
  final bool flexibleAllowed;

  /// One of [PlayInstallStatus].
  final int installStatus;
}

/// [AppUpdateService] over the `dev.khoj.pitaka/app_update` channels +
/// [AppInfo] gate.
final class PlayAppUpdateService implements AppUpdateService {
  /// Creates the service over the identity probe ([AppInfo] is injectable
  /// for tests; production passes the method-channel impl).
  const PlayAppUpdateService({required AppInfo appInfo}) : _appInfo = appInfo;

  /// Method-channel name shared with `AppUpdateChannel.kt` (play flavor).
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel(
    'dev.khoj.pitaka/app_update',
  );

  /// Event-channel name shared with `AppUpdateChannel.kt` (play flavor).
  @visibleForTesting
  static const EventChannel eventChannel = EventChannel(
    'dev.khoj.pitaka/app_update/install_state',
  );

  final AppInfo _appInfo;

  @override
  Future<bool> isEligible() async {
    // Order matters for tests/desktop: the platform check is free and keeps
    // the channel from ever being touched off Android.
    if (!Platform.isAndroid) return false;
    return AppUpdatePolicy.isPlayInstall(
      isAndroid: true,
      applicationId: await _appInfo.applicationId(),
    );
  }

  @override
  Future<AppUpdateAvailability> check() async {
    try {
      final reply = PlayUpdateCheck.fromChannel(
        await methodChannel.invokeMethod<Object>('checkForUpdate'),
      );
      if (reply == null) {
        debugPrint('app_update: checkForUpdate returned a malformed reply');
        return AppUpdateAvailability.none;
      }
      return availabilityFrom(reply);
    } on MissingPluginException {
      // No native handler: the fdroid flavor (inert twin), tests, desktop.
      return AppUpdateAvailability.none;
    } on PlatformException catch (e) {
      // No Play Store, sideloaded install, transient Play error — all
      // expected in the wild and all mean "stay silent" (debug log only,
      // no analytics/PII, §3).
      debugPrint('app_update: checkForUpdate failed: ${e.code}');
      return AppUpdateAvailability.none;
    }
  }

  @override
  Future<bool> startFlexibleDownload() async {
    try {
      // Resolves once the user accepts Play's consent dialog; progress then
      // arrives on [statusChanges]. A refusal is a PlatformException.
      await methodChannel.invokeMethod<void>('startFlexibleUpdate');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('app_update: startFlexibleUpdate failed: ${e.code}');
      return false;
    }
  }

  @override
  Stream<AppUpdateStatus> get statusChanges => eventChannel
      .receiveBroadcastStream()
      .map((Object? raw) => raw is int ? raw : PlayInstallStatus.unknown)
      .map(statusFromInstall);

  @override
  Future<void> completeUpdate() =>
      methodChannel.invokeMethod<void>('completeFlexibleUpdate');

  /// Maps Play's check result onto the flow's decisions (pure — unit-tested
  /// without a channel):
  ///  - a developer-triggered download already running is RESUMED, not
  ///    re-started (and its finished state offers the restart directly);
  ///  - an immediate-only update is treated as none: this app ships the
  ///    flexible flow exclusively (D2), so there is nothing to do;
  ///  - any code Play does not document is "unknown" → none.
  @visibleForTesting
  static AppUpdateAvailability availabilityFrom(PlayUpdateCheck check) {
    switch (check.updateAvailability) {
      case PlayUpdateAvailability.developerTriggeredUpdateInProgress:
        return check.installStatus == PlayInstallStatus.downloaded
            ? AppUpdateAvailability.downloaded
            : AppUpdateAvailability.inProgress;
      case PlayUpdateAvailability.updateAvailable:
        return check.flexibleAllowed
            ? AppUpdateAvailability.available
            : AppUpdateAvailability.none;
      default:
        return AppUpdateAvailability.none;
    }
  }

  /// Maps Play's install states onto the banner's coarse statuses (pure).
  /// `installed` means the update already landed (it fires after the
  /// restart), so there is nothing left to offer → silence. Unknown codes
  /// → silence as well.
  @visibleForTesting
  static AppUpdateStatus statusFromInstall(int status) {
    switch (status) {
      case PlayInstallStatus.pending:
      case PlayInstallStatus.downloading:
      case PlayInstallStatus.installing:
        return AppUpdateStatus.downloading;
      case PlayInstallStatus.downloaded:
        return AppUpdateStatus.downloaded;
      default:
        return AppUpdateStatus.idle;
    }
  }
}
