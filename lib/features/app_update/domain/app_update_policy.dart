/// Pure policy types for the Play in-app update flow (domain, S35).
///
/// Pure Dart, no Flutter/Play imports (AGENTS.md §3.1): the status the UI
/// renders, the check outcome the controller acts on, and the eligibility
/// rule that keeps the whole feature inert outside the Play flavor.
library;

/// UI-facing status of the flexible-update flow.
///
/// Deliberately COARSER than Play's own states: the banner renders only for
/// [downloading] and [downloaded]; everything else is silence. An update nag
/// must never become an error surface (fail safe: the worst outcome of a
/// bug here is "no banner", never "broken app").
enum AppUpdateStatus {
  /// Not a Play-Store Android install (fdroid flavor, iOS, desktop, tests):
  /// the feature is inert.
  ineligible,

  /// Eligible, and nothing to do: no update available, OR a check/download
  /// failed. The two are deliberately indistinguishable — errors stay
  /// silent by design.
  idle,

  /// A flexible download is running in the background (owned by the Play
  /// Store; the app stays fully usable).
  downloading,

  /// The download finished; a user-confirmed restart applies the update.
  downloaded,
}

/// What Play answered when asked about an update.
enum AppUpdateAvailability {
  /// No update, or none this flow can act on (e.g. immediate-only).
  none,

  /// An update is available and a flexible (background) download may start.
  available,

  /// A developer-triggered flexible download is ALREADY in progress (e.g.
  /// the app restarted mid-download) — resume observing, do not re-start.
  inProgress,

  /// The flexible download already finished; only the restart is missing.
  downloaded,
}

/// The eligibility rule for the Play in-app update flow (pure, unit-tested).
abstract final class AppUpdatePolicy {
  /// The Play-store applicationId (the `play` flavor). The fdroid flavor's
  /// id (`dev.khoj.pitaka.fdroid`) differs, has no Play listing, and must
  /// never run the update check — F-Droid's own client handles its updates.
  static const String playApplicationId = 'dev.khoj.pitaka';

  /// True only for an Android install whose applicationId is EXACTLY the
  /// play flavor's. A null/unknown applicationId (platform side missing)
  /// is NOT eligible: the gate fails safe toward "feature off".
  static bool isPlayInstall({
    required bool isAndroid,
    required String? applicationId,
  }) => isAndroid && applicationId == playApplicationId;
}
