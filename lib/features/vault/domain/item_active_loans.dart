/// The loans of ONE item that are still out, for the item's page (domain,
/// pure Dart; review finding P4-M3, decisions D103 and D104).
///
/// Why this exists (beginner note): an item can have several copies, so it
/// can be out with several borrowers at once. The item's page shows one
/// line for each of those loans, each with its own "Mark returned". Which
/// loans those are, in which order they stand and who has each copy is a
/// rule about loans, so it lives here and not in a widget.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';

/// One loan of an item that is still out, with the borrower who has it.
final class ActiveItemLoan {
  /// Creates the pair of a [loan] and its [borrower].
  const ActiveItemLoan({required this.loan, required this.borrower});

  /// The loan; not returned.
  final Loan loan;

  /// Who has the copy. Null when the vault holds no borrower with the
  /// loan's `borrowerId` (possible after a restore; Borrowed Items counts
  /// such a loan as "unresolved"). The loan can still be marked returned.
  final Borrower? borrower;
}

/// The loans of the item [itemId] in [data] that are not returned.
///
/// Ordered by due date, the earliest first and a loan without a due date
/// last; loans with the same due date stand in the order of their ids, so
/// the lines never change places between two looks.
List<ActiveItemLoan> activeLoansOfItem({
  required int itemId,
  required VaultData data,
}) {
  final borrowers = {
    for (final borrower in data.borrowers) borrower.id: borrower,
  };
  // A new list: the vault's own list must not be reordered.
  final loans = [
    for (final loan in data.loans)
      if (loan.itemId == itemId && !loan.isReturned) loan,
  ]..sort(_byDueDateThenId);
  return [
    for (final loan in loans)
      ActiveItemLoan(loan: loan, borrower: borrowers[loan.borrowerId]),
  ];
}

int _byDueDateThenId(Loan a, Loan b) {
  final dueA = a.dueDate;
  final dueB = b.dueDate;
  if (dueA != dueB) {
    if (dueA == null) return 1;
    if (dueB == null) return -1;
    return dueA.compareTo(dueB);
  }
  return a.id.compareTo(b.id);
}
