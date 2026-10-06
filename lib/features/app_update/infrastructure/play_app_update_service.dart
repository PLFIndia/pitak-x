/// Play-backed [AppUpdateService] (infrastructure, S35).
///
/// Side effects live here (AGENTS.md §3.1): the `in_app_update` plugin
/// (Google Play in-app updates API) and the platform identity probe. Every
/// expected platform failure — no Play Store, a non-Play install, a refused
/// or failed download — degrades to the safe negative, so the feature can
/// only ever go silent, never break the app.
///
/// Only the FLEXIBLE flow is wired (decision D2: background download, never
/// blocking). `performImmediateUpdate` is deliberately unused.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';

/// [AppUpdateService] over the `in_app_update` plugin + [AppInfo] gate.
final class PlayAppUpdateService implements AppUpdateService {
  /// Creates the service over the identity probe ([AppInfo] is injectable
  /// for tests; production passes the method-channel impl).
  const PlayAppUpdateService({required AppInfo appInfo}) : _appInfo = appInfo;

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
      return availabilityFrom(await InAppUpdate.checkForUpdate());
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
      return await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success;
    } on PlatformException catch (e) {
      debugPrint('app_update: startFlexibleUpdate failed: ${e.code}');
      return false;
    }
  }

  @override
  Stream<AppUpdateStatus> get statusChanges =>
      InAppUpdate.installUpdateListener.map(statusFromInstall);

  @override
  Future<void> completeUpdate() => InAppUpdate.completeFlexibleUpdate();

  /// Maps Play's check result onto the flow's decisions (pure — unit-tested
  /// without a channel):
  ///  - a developer-triggered download already running is RESUMED, not
  ///    re-started (and its finished state offers the restart directly);
  ///  - an immediate-only update is treated as none: this app ships the
  ///    flexible flow exclusively (D2), so there is nothing to do.
  @visibleForTesting
  static AppUpdateAvailability availabilityFrom(AppUpdateInfo info) {
    switch (info.updateAvailability) {
      case UpdateAvailability.developerTriggeredUpdateInProgress:
        return info.installStatus == InstallStatus.downloaded
            ? AppUpdateAvailability.downloaded
            : AppUpdateAvailability.inProgress;
      case UpdateAvailability.updateAvailable:
        return info.flexibleUpdateAllowed
            ? AppUpdateAvailability.available
            : AppUpdateAvailability.none;
      case UpdateAvailability.updateNotAvailable:
      case UpdateAvailability.unknown:
        return AppUpdateAvailability.none;
    }
  }

  /// Maps Play's install states onto the banner's coarse statuses (pure).
  /// `installed` means the update already landed (it fires after the
  /// restart), so there is nothing left to offer → silence.
  @visibleForTesting
  static AppUpdateStatus statusFromInstall(InstallStatus status) {
    switch (status) {
      case InstallStatus.pending:
      case InstallStatus.downloading:
      case InstallStatus.installing:
        return AppUpdateStatus.downloading;
      case InstallStatus.downloaded:
        return AppUpdateStatus.downloaded;
      case InstallStatus.installed:
      case InstallStatus.failed:
      case InstallStatus.canceled:
      case InstallStatus.unknown:
        return AppUpdateStatus.idle;
    }
  }
}
