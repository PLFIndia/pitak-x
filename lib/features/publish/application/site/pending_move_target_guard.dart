/// The one S9 rule that blocks a target mutation during pending recovery.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Refuses a setup/target change unless it is exactly the pending destination.
///
/// Why a shared object (beginner note): GitHub repo setup and Cloudflare Worker
/// setup ask the same question — "does the journal currently own this target?".
/// One implementation keeps the two answers from drifting, and an unreadable
/// journal fails closed instead of being mistaken for "no pending move".
final class PendingMoveTargetGuard {
  /// Creates the guard over the host journal.
  const PendingMoveTargetGuard(this._hostState);

  final PublishHostStateRepository _hostState;

  /// Right when there is no pending move, or [target] is one of its endpoints.
  Either<Failure, Unit> allows(PublishTarget target) {
    final loaded = _hostState.storedState();
    if (loaded case Left(value: final failure)) return Left(failure);
    final pending = loaded.toNullable()?.pendingMove;
    if (pending != null && !pending.involves(target)) {
      return const Left(ValidationFailure(MoveSiteMessages.targetMismatch));
    }
    return right(unit);
  }
}
