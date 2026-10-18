/// Membership confirmation (network domain use case; libNetwork.md §5.6
/// step 4, §5.1).
///
/// The user's answer to "'X' lists you as a member — show that you're a
/// member of X?": `confirmed` (published in my descriptor's `memberOf` on
/// the next publish), `declined` (never re-prompted), or — via the row's
/// "Reconsider" action — back to `pending` so the prompt appears again.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';

/// Moves one row's [NetworkLibrary.membership] state on the user's decision.
final class ConfirmMembershipUseCase {
  /// Creates the use case over its port.
  const ConfirmMembershipUseCase({required NetworkRepository repository})
    : _repository = repository;

  final NetworkRepository _repository;

  /// Applies [decision] to the row with [rowId].
  ///
  /// [decision] must be `confirmed`, `declined` or `pending` (Reconsider);
  /// `none` is rejected — a user action must never erase the membership
  /// signal back to "no idea" (that transition belongs to the refresh
  /// algorithm alone, which never produces it either: fail closed).
  /// A missing row is a typed [NotFoundFailure], never a throw.
  Future<Either<Failure, Unit>> call({
    required int rowId,
    required MembershipState decision,
  }) async {
    if (decision == MembershipState.none) {
      return const Left(ValidationFailure('Unknown membership decision'));
    }
    final rows = await _repository.loadAll();
    NetworkLibrary? row;
    for (final candidate in rows) {
      if (candidate.id == rowId) row = candidate;
    }
    if (row == null) return left(const NotFoundFailure());
    if (!_transitionAllowed(row.membership, decision)) {
      // Review Lows: the use case, not the UI, is the authority on which
      // moves exist. The model (§5.6 step 4): answer a PENDING question
      // (confirmed/declined), or Reconsider a DECLINED one back to pending.
      // `none` means the hub does not list me — declaring membership from
      // there would publish a `memberOf` the hub never claimed, so it is
      // refused like every other unlisted transition. Same-state is a
      // legal no-op (a double-tap is not an error).
      return const Left(
        ValidationFailure('That membership change is not available.'),
      );
    }
    final saved = await _repository.upsertBySiteUrl(
      row.copyWith(membership: decision),
    );
    return saved.map((_) => unit);
  }

  /// The legal membership moves (see the call site for the rationale).
  static bool _transitionAllowed(MembershipState from, MembershipState to) {
    if (from == to) return true; // idempotent no-op
    return switch ((from, to)) {
      (MembershipState.pending, MembershipState.confirmed) => true,
      (MembershipState.pending, MembershipState.declined) => true,
      (MembershipState.declined, MembershipState.pending) => true, // Reconsider
      _ => false,
    };
  }
}
