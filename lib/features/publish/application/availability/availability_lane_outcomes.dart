/// What the availability lane does with the outcome of one publish
/// (application layer; ADR 0019 Decisions 8 and 11, plan C.4 "When the timer
/// fires", step 4).
///
/// One table, kept apart from the scheduling so each stays readable:
///  - **live**: the sent set becomes "published"; retry reset; up to date;
///  - **going live**: the same, and GitHub starts its deferred check;
///    status going live;
///  - **already published**: the same, without a new GitHub spacing anchor;
///  - **not ready**: nothing saved changes, a stale file is removed (plan
///    S6), and the lane waits for a catalogue publish;
///  - **pending**: nothing saved changes; backoff, at its slowest when only
///    the user can repair the site;
///  - **blocked** (no host, a pending move): wait for a trigger.
///
/// A removal that succeeds while the switch is still off clears every saved
/// set (ADR 0019 Decision 9); if the switch went back on meanwhile, only the
/// published record is forgotten and a new pending set is kept.
library;

import 'package:pitaka/features/publish/application/availability/availability_lane_memory.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Applies one publish outcome to the lane's memory, retry state and status.
final class AvailabilityLaneOutcomes {
  /// Creates the handler over the lane's own parts.
  const AvailabilityLaneOutcomes({
    required AvailabilityLaneMemory memory,
    required AvailabilityLaneRetry retry,
    required int Function() clock,
    required bool? Function() enabled,
    required void Function(AvailabilityLaneStatus) emit,
    required void Function(DeferredVerificationRequest, AvailabilityUpdate)
    startProof,
  }) : _memory = memory,
       _retry = retry,
       _clock = clock,
       _enabled = enabled,
       _emit = emit,
       _startProof = startProof;

  final AvailabilityLaneMemory _memory;
  final AvailabilityLaneRetry _retry;
  final int Function() _clock;
  final bool? Function() _enabled;
  final void Function(AvailabilityLaneStatus) _emit;
  final void Function(DeferredVerificationRequest, AvailabilityUpdate)
  _startProof;

  /// Applies [run], the outcome of publishing [update].
  Future<void> apply(AvailabilityUpdate update, AvailabilityRun run) async {
    switch (run) {
      case AvailabilityRunBlocked(:final reason):
        // Gates a/c: no host, a pending move. Changing either is a trigger.
        _retry.reset();
        _emit(AvailabilityLaneNotReady(reason));
      case AvailabilityRunFinished(
        :final target,
        :final result,
        :final removal,
      ):
        await _result(update, target, result);
        if (removal != null) await _staleRemoval(removal);
    }
  }

  Future<void> _result(
    AvailabilityUpdate update,
    PublishTarget target,
    AvailabilityPublishResult result,
  ) async {
    switch (result) {
      case AvailabilityLive(:final acceptedAt):
        await _sent(update, target, acceptedAt: acceptedAt, live: true);
      case AvailabilityGoingLive(:final acceptedAt, :final verification):
        await _sent(update, target, acceptedAt: acceptedAt, live: false);
        if (verification != null) _startProof(verification, update);
      case AvailabilityAlreadyPublished():
        await _sent(update, target, acceptedAt: null, live: true);
      case AvailabilityNotReady(:final reason):
        // Wait for a catalogue publish; a timer cannot fix this (AV11).
        _retry
          ..reset()
          ..waitingForCatalogue = true;
        _emit(AvailabilityLaneNotReady(reason));
      case final AvailabilityPending pending:
        _failed(pending);
    }
  }

  /// The stale file removed after a "not ready" write (plan S6), or still
  /// to remove.
  Future<void> _staleRemoval(AvailabilityPublishResult removal) async {
    switch (removal) {
      case AvailabilityLive() || AvailabilityAlreadyPublished():
        await _memory.forgetPublished();
      case AvailabilityGoingLive(:final verification):
        await _memory.forgetPublished();
        if (verification != null) {
          _startProof(verification, const AvailabilityDelete());
        }
      case AvailabilityNotReady():
        // A removal has no gate 7b, so this cannot happen; nothing was sent.
        break;
      case final AvailabilityPending pending:
        // The dangerous file is still live: retry on the backoff, which runs
        // the write (still "not ready") and this removal again.
        _retry.waitingForCatalogue = false;
        _failed(pending);
    }
  }

  Future<void> _sent(
    AvailabilityUpdate update,
    PublishTarget target, {
    required int? acceptedAt,
    required bool live,
  }) async {
    _retry.reset();
    switch (update) {
      case AvailabilityWrite(:final snapshot):
        await _memory.recordWrite(
          sent: snapshot,
          target: target,
          acceptedAt: acceptedAt,
        );
        _emit(
          live
              ? AvailabilityLaneUpToDate(snapshot.asOf)
              : AvailabilityLaneGoingLive(snapshot.asOf),
        );
      case AvailabilityDelete() when _enabled() == false:
        await _memory.clearSets();
        _emit(const AvailabilityLaneOff());
      case AvailabilityDelete():
        // Switched back on meanwhile: keep any new pending set.
        await _memory.forgetPublished();
    }
  }

  void _failed(AvailabilityPending pending) {
    _retry.failed(pending.reason, repair: pending.needsRepair, at: _clock());
    _emit(AvailabilityLanePending(pending.reason));
  }
}
