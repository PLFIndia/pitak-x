/// The worker-owned state document of the background event check
/// (PLAN.md §1, `events_watch_state.json`).
///
/// Ownership rule (beginner note): ONLY the worker's serialized reducer
/// writes this document; the foreground only reads it to show status.
library;

import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';

/// Why the last run stopped early, when it did. Shown as one safe sentence.
enum RecoveryNotice {
  /// The previous state file was unreadable or oversized and was replaced
  /// by an empty one; earlier pending alerts (if any) were lost.
  stateReset,
}

/// Coarse summary of the last worker run for Settings.
final class LastRunOutcome {
  /// Creates a summary.
  const LastRunOutcome({
    required this.finishedAt,
    required this.checked,
    required this.withheld,
    required this.failed,
    required this.capacityExceeded,
  });

  /// Epoch millis when the run finished.
  final int finishedAt;

  /// Sites with an authoritative read this run.
  final int checked;

  /// Sites whose content could not be diffed this run.
  final int withheld;

  /// Sites whose fetch failed this run.
  final int failed;

  /// True when the saved-library cap was exceeded and nothing was checked.
  final bool capacityExceeded;

  /// Strict gate for stored input.
  static LastRunOutcome? validate({
    required Object? finishedAt,
    required Object? checked,
    required Object? withheld,
    required Object? failed,
    required Object? capacityExceeded,
  }) {
    if (finishedAt is! int || finishedAt < 0) return null;
    for (final count in [checked, withheld, failed]) {
      if (count is! int || count < 0 || count > 100000) return null;
    }
    if (capacityExceeded is! bool) return null;
    return LastRunOutcome(
      finishedAt: finishedAt,
      checked: checked! as int,
      withheld: withheld! as int,
      failed: failed! as int,
      capacityExceeded: capacityExceeded,
    );
  }
}

/// Immutable whole-document state.
final class EventsWatchState {
  /// Creates a state. Lists are copied and made unmodifiable.
  EventsWatchState({
    required this.observedToken,
    required this.generation,
    required List<SiteWatchStatus> sites,
    required List<PendingChange> pending,
    required this.revocationToken,
    required this.recoveryNotice,
    required this.lastRun,
  }) : sites = List.unmodifiable(sites),
       pending = List.unmodifiable(pending);

  /// The recovery document written over an unreadable one (PLAN.md §6).
  factory EventsWatchState.recovered({required WatchSettingsToken token}) =>
      EventsWatchState(
        observedToken: token,
        generation: null,
        sites: const [],
        pending: const [],
        revocationToken: null,
        recoveryNotice: RecoveryNotice.stateReset,
        lastRun: null,
      );

  /// A state with nothing in it.
  factory EventsWatchState.empty() => EventsWatchState(
    observedToken: null,
    generation: null,
    sites: const [],
    pending: const [],
    revocationToken: null,
    recoveryNotice: null,
    lastRun: null,
  );

  /// Schema this build reads and writes.
  static const int schemaVersion = 1;

  /// The settings token the worker last reconciled against, or null.
  final WatchSettingsToken? observedToken;

  /// Name of the data generation the site rows belong to, or null.
  final String? generation;

  /// Per-library status, in stable URL order.
  final List<SiteWatchStatus> sites;

  /// Not-yet-submitted alerts.
  final List<PendingChange> pending;

  /// Set when the worker observed definitive permission loss under this
  /// token; a later run under the SAME token stops without fetching, even
  /// if permission was re-granted (PLAN.md §6).
  final WatchSettingsToken? revocationToken;

  /// Visible loss notice, or null.
  final RecoveryNotice? recoveryNotice;

  /// Summary of the last finished run, or null.
  final LastRunOutcome? lastRun;

  /// A state with nothing in it.

  /// The recovery document written over an unreadable one (PLAN.md §6).

  /// Status for [siteUrl], or null.
  SiteWatchStatus? siteAt(String siteUrl) {
    for (final site in sites) {
      if (site.siteUrl == siteUrl) return site;
    }
    return null;
  }

  /// Pending entries belonging to [siteUrl].
  List<PendingChange> pendingFor(String siteUrl) =>
      pending.where((change) => change.siteUrl == siteUrl).toList();

  /// Copy with selected fields replaced. The `clear*` flags exist because a
  /// null argument cannot distinguish "keep" from "set to null".
  EventsWatchState copyWith({
    WatchSettingsToken? observedToken,
    String? generation,
    List<SiteWatchStatus>? sites,
    List<PendingChange>? pending,
    WatchSettingsToken? revocationToken,
    RecoveryNotice? recoveryNotice,
    LastRunOutcome? lastRun,
    bool clearGeneration = false,
    bool clearRevocationToken = false,
    bool clearRecoveryNotice = false,
  }) => EventsWatchState(
    observedToken: observedToken ?? this.observedToken,
    generation: clearGeneration ? null : (generation ?? this.generation),
    sites: sites ?? this.sites,
    pending: pending ?? this.pending,
    revocationToken: clearRevocationToken
        ? null
        : (revocationToken ?? this.revocationToken),
    recoveryNotice: clearRecoveryNotice
        ? null
        : (recoveryNotice ?? this.recoveryNotice),
    lastRun: lastRun ?? this.lastRun,
  );
}
