/// The in-app update seam (domain, S35).
///
/// Why an interface (beginner note): the real implementation talks to the
/// Google Play API through the `in_app_update` plugin, which cannot run in
/// unit tests (no Play Store on the host). Everything the controller does —
/// when to check, when to start the download, how to react to state changes
/// — is tested against a fake of THIS interface instead. Same pattern as
/// the repositories (§3.3): declared in domain, implemented in
/// infrastructure, faked in tests.
library;

import 'package:pitaka/features/app_update/domain/app_update_policy.dart';

/// Port to the platform's app-update machinery (Play on Android).
///
/// Contract: implementations NEVER throw for expected platform failures
/// (no Play Store, non-Play install, transient errors) — they return the
/// safe negative (`false` / [AppUpdateAvailability.none]) so the feature
/// degrades to silence. The controller adds a catch-all on top.
abstract interface class AppUpdateService {
  /// Whether this install may use the flow at all (Android + play flavor).
  Future<bool> isEligible();

  /// Asks the store whether an update is available / a download is already
  /// running or finished.
  Future<AppUpdateAvailability> check();

  /// Starts the background (flexible) download; true when it was accepted.
  /// The user keeps using the app either way — never blocking (decision D2).
  Future<bool> startFlexibleDownload();

  /// Install-state changes while a flexible download lives (progress,
  /// completion, failure). Emits only [AppUpdateStatus.downloading],
  /// [AppUpdateStatus.downloaded] and [AppUpdateStatus.idle] (a failed or
  /// canceled download degrades to silence).
  Stream<AppUpdateStatus> get statusChanges;

  /// Applies a fully-downloaded update: hands over to the store, which
  /// installs and restarts the app.
  Future<void> completeUpdate();
}
