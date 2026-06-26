/// Outcome of a successful backup restore (AGENTS.md §3.1, pure Dart).
library;

import 'package:pitaka/features/vault/domain/loan_integrity.dart';

/// Counts + integrity findings from an applied restore.
class RestoreSummary {
  /// Creates a restore summary.
  const RestoreSummary({
    required this.booksRestored,
    required this.wishlistRestored,
    required this.borrowersRestored,
    required this.loansRestored,
    this.danglingLoans = const [],
  });

  /// Number of library books written.
  final int booksRestored;

  /// Number of wishlist entries written.
  final int wishlistRestored;

  /// Number of vault borrowers read.
  final int borrowersRestored;

  /// Number of vault loans read.
  final int loansRestored;

  /// Loans whose `bookId`/`borrowerId` did not resolve after restore. Empty
  /// means full cross-DB referential integrity (the expected case).
  final List<DanglingLoan> danglingLoans;

  /// True when every restored loan references an existing book and borrower.
  bool get isIntact => danglingLoans.isEmpty;
}
