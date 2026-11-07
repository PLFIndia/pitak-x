/// What the Settings tile shows for background event alerts (PLAN.md §7).
/// Immutable; built only by `EventsWatchController`.
library;

import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';

/// The one state the switch and its helper text are derived from.
enum EventsWatchPhase {
  /// Not available on this platform; hide the group.
  unsupported,

  /// First run with saved libraries and no settings yet: offer default ON
  /// by showing the explanation (decision 1).
  setupOffered,

  /// User turned it off, or declined the offer.
  off,

  /// ON and the periodic job is registered.
  on,

  /// ON in settings but no job is registered (failed disable save, job
  /// loss, earlier empty-set cancellation). Needs explicit Resume
  /// (decision 14).
  notScheduled,

  /// Nothing to watch: no user-saved libraries. The job is not registered.
  noLibraries,

  /// Notifications are denied or the channel is blocked; settings were
  /// turned OFF. Offer system settings.
  blocked,

  /// Settings/state file from a newer build: update required.
  updateRequired,

  /// Settings file corrupt: offer reset.
  settingsCorrupt,

  /// Settings could not be read or written right now.
  storageError,
}

/// Summary of the worker's last run for the tile's helper text.
final class EventsWatchStatus {
  /// Creates a status.
  const EventsWatchStatus({
    required this.lastRun,
    required this.withheldSites,
    required this.failedSites,
    required this.recoveryNotice,
    required this.pendingAlerts,
  });

  /// Last finished run, or null.
  final LastRunOutcome? lastRun;

  /// Sites whose last outcome was withheld.
  final int withheldSites;

  /// Sites whose last outcome was failed.
  final int failedSites;

  /// Visible loss notice, or null.
  final RecoveryNotice? recoveryNotice;

  /// Alerts detected but not yet submitted.
  final int pendingAlerts;

  /// An empty status (no state file yet).
  static const EventsWatchStatus none = EventsWatchStatus(
    lastRun: null,
    withheldSites: 0,
    failedSites: 0,
    recoveryNotice: null,
    pendingAlerts: 0,
  );
}

/// Immutable view.
final class EventsWatchView {
  /// Creates a view.
  const EventsWatchView({
    required this.phase,
    required this.status,
    this.needsExplanation = false,
  });

  /// Current phase.
  final EventsWatchPhase phase;

  /// Last-run status (best effort; `none` when unreadable).
  final EventsWatchStatus status;

  /// True when an explicit enable must show the explanation first.
  final bool needsExplanation;

  /// The view for unsupported platforms.
  static const EventsWatchView unsupported = EventsWatchView(
    phase: EventsWatchPhase.unsupported,
    status: EventsWatchStatus.none,
  );

  /// Whether the switch renders as ON.
  bool get switchOn =>
      phase == EventsWatchPhase.on || phase == EventsWatchPhase.notScheduled;
}
