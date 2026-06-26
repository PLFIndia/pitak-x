/// Cross-DB loan↔book integrity (AGENTS.md / PLAN.md cross-DB rule).
///
/// Books live in the Drift database; loans live in the encrypted Rust vault.
/// There is no DB-level foreign key across that boundary, so referential
/// integrity is enforced here in the application layer — exactly as the Kotlin
/// app does across its separate Room/SQLCipher databases.
///
/// Pure Dart, no IO: callers pass in the set of known book ids and the loans to
/// check. This keeps the rule unit-testable without the FFI or any database.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// A loan whose referenced book or borrower no longer exists.
class DanglingLoan {
  /// Creates a dangling-loan record.
  const DanglingLoan({
    required this.loan,
    required this.missingBook,
    required this.missingBorrower,
  });

  /// The offending loan.
  final Loan loan;

  /// True if [Loan.bookId] is not among the known book ids.
  final bool missingBook;

  /// True if [Loan.borrowerId] is not among the known borrower ids.
  final bool missingBorrower;
}

/// Application-layer guard for cross-DB loan references.
abstract final class LoanIntegrity {
  /// Returns every loan whose `bookId` is not in [knownBookIds] or whose
  /// `borrowerId` is not in [knownBorrowerIds].
  ///
  /// Used after a restore (when the vault and library are imported from
  /// separate sources) and before surfacing loans in the UI, so a loan can
  /// never silently point at a vanished book/borrower.
  static List<DanglingLoan> findDangling({
    required Iterable<Loan> loans,
    required Set<int> knownBookIds,
    required Set<int> knownBorrowerIds,
  }) {
    final result = <DanglingLoan>[];
    for (final loan in loans) {
      final missingBook = !knownBookIds.contains(loan.bookId);
      final missingBorrower = !knownBorrowerIds.contains(loan.borrowerId);
      if (missingBook || missingBorrower) {
        result.add(
          DanglingLoan(
            loan: loan,
            missingBook: missingBook,
            missingBorrower: missingBorrower,
          ),
        );
      }
    }
    return result;
  }

  /// True if every loan references an existing book and borrower.
  static bool isIntact({
    required Iterable<Loan> loans,
    required Set<int> knownBookIds,
    required Set<int> knownBorrowerIds,
  }) => findDangling(
    loans: loans,
    knownBookIds: knownBookIds,
    knownBorrowerIds: knownBorrowerIds,
  ).isEmpty;
}
