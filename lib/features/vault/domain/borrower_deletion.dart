/// Borrower-deletion rule (domain, pure Dart, AGENTS.md §3.1).
///
/// A loan row is never removed when a book comes back — `returnedDate` is
/// filled in and the row stays as history. So "can this borrower be deleted?"
/// is not "do they have loans?" but "do they still have books OUT?":
///
///  - any loan with `returnedDate == null` → deletion is blocked (a book cannot
///    be out to nobody);
///  - only returned loans → deletion is allowed, and that history goes with
///    the borrower (the Rust core removes both in one transaction).
///
/// The Rust core enforces the same rule authoritatively; this Dart copy exists
/// so the UI can explain the outcome BEFORE asking for confirmation ("this
/// also removes 3 returned-loan records") instead of surfacing a raw failure.
/// Pure and side-effect-free, so it is trivially testable.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Reason a borrower cannot be deleted while books are still out. Shown to the
/// user as-is; kept in sync with `ACTIVE_LOANS_BLOCK_DELETE` in the Rust core
/// so the pre-check and the authoritative check say the same thing.
const String activeLoansBlockDeleteMessage =
    'This borrower still has books out. Mark those loans returned first.';

/// What deleting a given borrower would do, computed from their loans.
///
/// Sealed so the UI must handle both outcomes explicitly (no forgotten case).
sealed class BorrowerDeletion {
  const BorrowerDeletion();

  /// Decides the outcome for [borrowerId] given the vault's [loans] (any
  /// borrower's loans may be passed; others are ignored).
  factory BorrowerDeletion.plan({
    required int borrowerId,
    required Iterable<Loan> loans,
  }) {
    var active = 0;
    var returned = 0;
    for (final loan in loans) {
      if (loan.borrowerId != borrowerId) continue;
      if (loan.isReturned) {
        returned++;
      } else {
        active++;
      }
    }
    if (active > 0) return BorrowerDeletionBlocked(activeLoanCount: active);
    return BorrowerDeletionAllowed(returnedLoanCount: returned);
  }
}

/// Deletion is refused: [activeLoanCount] books are still out.
final class BorrowerDeletionBlocked extends BorrowerDeletion {
  /// Creates a blocked outcome.
  const BorrowerDeletionBlocked({required this.activeLoanCount});

  /// How many loans are not yet returned (always ≥ 1).
  final int activeLoanCount;
}

/// Deletion may proceed; [returnedLoanCount] history rows go with the borrower.
final class BorrowerDeletionAllowed extends BorrowerDeletion {
  /// Creates an allowed outcome.
  const BorrowerDeletionAllowed({required this.returnedLoanCount});

  /// How many returned-loan records will be removed alongside the borrower
  /// (0 when the borrower never borrowed anything).
  final int returnedLoanCount;
}
