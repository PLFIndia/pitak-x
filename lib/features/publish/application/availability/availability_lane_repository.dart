/// The ONE writer of the availability lane's saved state (application layer;
/// ADR 0019 Decisions 8 and 9, plan C.4).
///
/// Why a single writer (beginner note): two parts of the app change the
/// saved state. The lane saves its pending set, and every accepted GitHub
/// commit — from any publish — is added to the hourly budget. Each change is
/// "read the state, change one field, write it back". If two of those ran at
/// the same time, the second write would silently drop the first change.
/// So every change goes through `update`, which runs them one after another
/// on its own queue.
///
/// Reading rules come from the domain (`AvailabilityLaneState.decode`): a
/// damaged value is [AvailabilityLaneUnreadable] and carries no data. An
/// update then starts from the EMPTY state: nothing pending and nothing
/// published, which makes the lane wait for live loan counts to compute a
/// fresh set (plan C.4). It can never turn into an empty "not available"
/// list, because "nothing pending" publishes nothing.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_store.dart';

/// Serialised access to the [AvailabilityLaneStore].
final class AvailabilityLaneRepository {
  /// Creates the repository over [store].
  AvailabilityLaneRepository(AvailabilityLaneStore store) : _store = store;

  final AvailabilityLaneStore _store;

  /// Orders every read and write of this repository (FIFO).
  final SerialOpQueue _queue = SerialOpQueue();

  /// Reads the saved state, in order with every pending [update].
  Future<AvailabilityLaneRead> read() => _queue.enqueue(_store.read);

  /// Applies [change] to the saved state and writes the result, as ONE step
  /// that no other update can interleave with.
  ///
  /// An absent or unreadable state is passed to [change] as the empty state
  /// (see the library comment). Returns the written state, or the store's
  /// failure; a failed write leaves the stored value as it was.
  Future<Either<Failure, AvailabilityLaneState>> update(
    AvailabilityLaneState Function(AvailabilityLaneState current) change,
  ) => _queue.enqueue(() async {
    final current = switch (await _store.read()) {
      AvailabilityLaneLoaded(:final state) => state,
      AvailabilityLaneAbsent() ||
      AvailabilityLaneUnreadable() => AvailabilityLaneState(),
    };
    final next = change(current);
    final written = await _store.write(next);
    return written.map((_) => next);
  });

  /// Adds one accepted GitHub commit to the hourly budget (AV6).
  ///
  /// Best effort on purpose: the commit already happened, and the budget is a
  /// courtesy limit, so a failed save is logged (type only) and never turned
  /// into a publish failure.
  Future<void> recordGitHubCommit(int acceptedAt) async {
    final saved = await update((state) => state.withGitHubCommit(acceptedAt));
    if (saved.isLeft()) {
      appLog('availability lane: GitHub commit time not saved');
    }
  }
}
