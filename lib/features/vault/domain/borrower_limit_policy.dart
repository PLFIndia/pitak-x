/// Per-borrower active-loan limit and its enforcement mode (pure Dart).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// What lending does when a borrower is at or over the configured limit.
enum BorrowerLimitAction {
  /// Ask for named confirmation, then allow an explicit override.
  warn,

  /// Refuse without an override and recheck inside the vault write queue.
  refuse,
}

/// Result of applying the policy to one borrower's active-loan count.
enum BorrowerLimitCheck {
  /// The requested loan may proceed.
  allowed,

  /// Warn mode needs the user's explicit confirmation before any write.
  needsConfirmation,

  /// Refuse mode forbids the requested loan.
  refused,
}

/// Safe recovery copy shared by both lending gates.
const borrowerLimitPolicyRecoveryMessage =
    'Lending rules could not be read. Open Lending rules and save them again.';

/// How many items one borrower may have out at once, and what to do at the cap.
final class BorrowerLimitPolicy {
  const BorrowerLimitPolicy._({
    required this.maxActiveLoans,
    required this.action,
  });

  /// Smallest permitted active-loan limit.
  static const minLimit = 1;

  /// Largest permitted active-loan limit.
  static const maxLimit = 99;

  /// Disabled policy used when no preference document exists.
  static const off = BorrowerLimitPolicy._(
    maxActiveLoans: null,
    action: BorrowerLimitAction.warn,
  );

  /// Null means off; otherwise the borrower cap is 1–99 active loans.
  final int? maxActiveLoans;

  /// Whether the cap asks for confirmation or refuses without an override.
  final BorrowerLimitAction action;

  /// True when a numeric cap is configured.
  bool get isOn => maxActiveLoans != null;

  /// Ingress gate: null means off; only 1–99 is accepted for an enabled cap.
  static Either<ValidationFailure, BorrowerLimitPolicy> validate({
    required int? maxActiveLoans,
    required BorrowerLimitAction action,
  }) {
    final limit = maxActiveLoans;
    if (limit != null && (limit < minLimit || limit > maxLimit)) {
      return left(
        const ValidationFailure('Enter a limit from 1 to 99, or turn it off.'),
      );
    }
    return right(BorrowerLimitPolicy._(maxActiveLoans: limit, action: action));
  }

  /// Off/under allows; Warn needs confirmation at/over unless acknowledged;
  /// Refuse rejects at/over even when a Warn acknowledgement is supplied.
  BorrowerLimitCheck check({
    required int activeLoans,
    bool warningAcknowledged = false,
  }) {
    final limit = maxActiveLoans;
    if (limit == null || activeLoans < limit) {
      return BorrowerLimitCheck.allowed;
    }
    return switch (action) {
      BorrowerLimitAction.warn =>
        warningAcknowledged
            ? BorrowerLimitCheck.allowed
            : BorrowerLimitCheck.needsConfirmation,
      BorrowerLimitAction.refuse => BorrowerLimitCheck.refused,
    };
  }
}

/// Shared refusal copy so the outer and FIFO gates cannot drift.
String borrowerLimitRefusalMessage({
  required int activeLoans,
  required int limit,
}) {
  final noun = activeLoans == 1 ? 'item' : 'items';
  return 'This borrower has $activeLoans $noun out; your limit is $limit. '
      'Mark one returned before lending another.';
}
