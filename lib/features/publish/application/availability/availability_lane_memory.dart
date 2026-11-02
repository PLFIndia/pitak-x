/// What the availability lane remembers (application layer; ADR 0019
/// Decision 9, plan C.4 "Lane store").
///
/// Two copies on purpose (beginner note): the copy in memory is the truth
/// while the app runs, and every change is also written to the store so it
/// survives the vault locking and an app restart (AV7). If a write fails,
/// the lane still publishes from memory; only a restart before the publish
/// would lose the set, and the next loan change computes it again.
///
/// All writes go through the [AvailabilityLaneRepository], the one writer
/// that also records GitHub commits, so neither side overwrites the other.
library;

import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_pacing.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// The lane's remembered sets, mirrored to the store.
final class AvailabilityLaneMemory {
  /// Creates the memory over [repository]; call [load] once before use.
  AvailabilityLaneMemory(AvailabilityLaneRepository repository)
    : _repository = repository;

  final AvailabilityLaneRepository _repository;

  AvailabilitySnapshot? _pending;
  AvailabilityPublished? _published;
  bool _noticeShown = false;
  bool _storeUnreadable = false;

  /// The set waiting to be published, or null.
  AvailabilitySnapshot? get pending => _pending;

  /// The last set this phone published, or null.
  AvailabilityPublished? get published => _published;

  /// True once the one-time notice was dismissed.
  bool get noticeShown => _noticeShown;

  /// True when the site may still show a file this lane wrote. A store that
  /// could not be read cannot say, so it counts (the runner's local record
  /// check that follows is cheap and sends nothing when there is no file).
  bool get removalDue =>
      _pending != null || _published != null || _storeUnreadable;

  /// Loads the saved state. A damaged store loads NOTHING (the domain
  /// decoder's rule): the lane then waits for live loan counts.
  Future<void> load() async {
    switch (await _repository.read()) {
      case AvailabilityLaneLoaded(:final state):
        _pending = state.pending;
        _published = state.published;
        _noticeShown = state.noticeShown;
      case AvailabilityLaneUnreadable():
        _storeUnreadable = true;
      case AvailabilityLaneAbsent():
        break;
    }
  }

  /// The newest GitHub commit times (every section), for the hourly budget.
  /// Read fresh each time: every GitHub commit adds one through the
  /// repository, not through this memory.
  Future<List<int>> gitHubCommitTimes() async =>
      switch (await _repository.read()) {
        AvailabilityLaneLoaded(:final state) => state.gitHubCommitTimes,
        AvailabilityLaneAbsent() || AvailabilityLaneUnreadable() => const [],
      };

  /// Makes [snapshot] the set waiting to be published, and saves it FIRST
  /// (AV7), before anything is scheduled.
  Future<void> keepPending(AvailabilitySnapshot snapshot) async {
    _pending = snapshot;
    await _save((state) => state.withPending(snapshot));
  }

  /// Records that [sent] reached [target]. [acceptedAt] is when the host
  /// accepted it, or null when nothing needed sending: the GitHub spacing
  /// then keeps its earlier anchor (or none).
  ///
  /// A newer pending set saved while the publish ran stays pending.
  Future<void> recordWrite({
    required AvailabilitySnapshot sent,
    required PublishTarget target,
    required int? acceptedAt,
  }) async {
    final previous = _published;
    final anchor =
        acceptedAt ??
        (previous != null && previous.describes(target)
            ? previous.publishedAt
            : 0);
    final record = AvailabilityPublished.of(
      target: target,
      snapshot: sent,
      publishedAt: anchor,
    );
    _published = record;
    final pending = _pending;
    if (pending != null &&
        pending.sameKeysAs(sent) &&
        pending.asOf == sent.asOf) {
      _pending = null;
    }
    await _save((state) => state.afterPublished(sent: sent, record: record));
  }

  /// The switch-off removal is on the site: forget every saved set, so
  /// turning the lane back on never publishes an old one (ADR 0019
  /// Decision 9).
  Future<void> clearSets() async {
    _pending = null;
    _published = null;
    await _save((state) => state.withoutSnapshots());
  }

  /// This lane's file was removed while the lane stays on (a stale file
  /// after gate 7b, or a removal that finished after the switch went back
  /// on): no set of ours is on the site, but a pending one still goes out.
  Future<void> forgetPublished() async {
    _published = null;
    await _save((state) => state.withoutPublished());
  }

  /// Marks the one-time notice as shown, for good.
  Future<void> markNoticeShown() async {
    _noticeShown = true;
    await _save((state) => state.withNoticeShown());
  }

  Future<void> _save(
    AvailabilityLaneState Function(AvailabilityLaneState) change,
  ) async {
    final saved = await _repository.update(change);
    if (saved.isRight()) {
      // A successful write replaced any damaged value.
      _storeUnreadable = false;
    } else {
      // Memory still holds the truth for this run (see the library comment).
      appLog('availability lane: state not saved');
    }
  }
}

/// The lane's retry bookkeeping for this app run (AV11). Not saved: the
/// backoff lasts "while the app runs" by design (ADR 0019 Decision 8).
final class AvailabilityLaneRetry {
  /// Failed publishes in a row since the last success.
  int failures = 0;

  /// When the last failure ended (epoch milliseconds), or null.
  int? lastFailureAt;

  /// The last failure's fixed sentence, or null.
  String? reason;

  /// True when the last failure needs the user's repair (plan S6).
  bool needsRepair = false;

  /// True after "not ready": only a catalogue publish, a new loan change or
  /// the button may retry, never a timer or a resume (each try would cost
  /// network calls that cannot succeed).
  bool waitingForCatalogue = false;

  /// Forgets every failure (after a success, or on a deliberate trigger).
  void reset() {
    failures = 0;
    lastFailureAt = null;
    reason = null;
    needsRepair = false;
  }

  /// Records one failure ending at [at]. A site only the user can repair
  /// starts at the slowest backoff step (10 min) instead of probing every
  /// minute.
  void failed(String why, {required bool repair, required int at}) {
    // The failure count that selects the last (slowest) backoff step.
    final slowest = AvailabilityPacing.retryBackoff.length;
    failures = repair && failures + 1 < slowest ? slowest : failures + 1;
    lastFailureAt = at;
    reason = why;
    needsRepair = repair;
  }
}
