/// The Play flexible-update controller (application layer, S35).
///
/// One check per app launch, then reaction to Play's install-state stream.
/// The POLICY lives here (when to check, auto-start the background download,
/// when to offer the restart); the platform mechanics live behind the
/// [AppUpdateService] seam; the banner only renders [AppUpdateStatus].
///
/// `keepAlive` (justified per §4): the session's single update check and an
/// in-flight download observation must survive navigation — an autoDispose
/// controller would re-check on every library-page visit (Play API spam) and
/// drop the stream subscription mid-download.
///
/// FAIL SAFE everywhere: every error path lands in [AppUpdateStatus.idle]
/// (banner hidden). An update nag must never become an error surface — the
/// worst outcome of a bug in this flow is "no banner", and the Play Store's
/// own update notification remains as the fallback.
library;

import 'dart:async' show StreamSubscription, unawaited;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_controller.g.dart';

/// Drives the check → background-download → restart-offer flow.
@Riverpod(keepAlive: true)
class AppUpdateController extends _$AppUpdateController {
  StreamSubscription<AppUpdateStatus>? _subscription;
  bool _dismissed = false;

  @override
  AppUpdateStatus build() {
    ref.onDispose(() => _subscription?.cancel());
    // Kick off the async flow without blocking the first frame; `ineligible`
    // (banner hidden) is the honest state until the gate says otherwise.
    unawaited(_run());
    return AppUpdateStatus.ineligible;
  }

  Future<void> _run() async {
    final service = ref.read(appUpdateServiceProvider);
    try {
      if (!await service.isEligible()) return; // fdroid/iOS/desktop/tests
      state = AppUpdateStatus.idle;
      // Observe install-state for the whole session: covers both a download
      // started below AND one already running from a previous launch.
      _subscription = service.statusChanges.listen(
        (status) {
          if (!_dismissed) state = status;
        },
        onError: (Object _) {}, // silence by design; idle stays
      );
      switch (await service.check()) {
        case AppUpdateAvailability.none:
          break; // idle — nothing to do
        case AppUpdateAvailability.available:
          // D2: the download starts AUTOMATICALLY in the background; the
          // banner only informs. A refusal/failure returns to silence.
          state = AppUpdateStatus.downloading;
          if (!await service.startFlexibleDownload()) {
            state = AppUpdateStatus.idle;
          }
        case AppUpdateAvailability.inProgress:
          state = AppUpdateStatus.downloading;
        case AppUpdateAvailability.downloaded:
          state = AppUpdateStatus.downloaded;
      }
    } on Object {
      // Catch-all (belt and braces over the service's own safe negatives):
      // unexpected errors also degrade to silence, never to the UI.
      state = AppUpdateStatus.idle;
    }
  }

  /// "Restart" tapped: hands over to the Play Store, which installs the
  /// downloaded update and restarts the app. A failure degrades to silence;
  /// the next launch re-checks and re-offers.
  Future<void> restartToUpdate() async {
    try {
      await ref.read(appUpdateServiceProvider).completeUpdate();
    } on Object {
      state = AppUpdateStatus.idle;
    }
  }

  /// Banner dismissed: hidden for the REST of this session (the user's
  /// choice is respected — the stream cannot re-show it). Any download
  /// already running continues inside the Play Store regardless, and the
  /// next launch re-checks and re-offers.
  void dismiss() {
    _dismissed = true;
    state = AppUpdateStatus.idle;
  }
}
