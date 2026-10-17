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
    final saved = await _repository.upsertBySiteUrl(
      row.copyWith(membership: decision),
    );
    return saved.map((_) => unit);
  }
}
