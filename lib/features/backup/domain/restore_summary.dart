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
    this.existingVaultKept = false,
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

  /// True when the archive had no vault and the device's vault was retained.
  /// M03: successful retention now requires a fresh unlocked integrity check
  /// and preservation of every loan's book identity, including returned loans.
  final bool existingVaultKept;

  /// True when restored loans resolve, or retained loan links were verified
  /// and preserved. A retained but unchecked vault can no longer succeed.
  bool get isIntact => danglingLoans.isEmpty;
}
