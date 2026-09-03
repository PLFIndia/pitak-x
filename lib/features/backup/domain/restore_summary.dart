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

  /// True when the archive carried NO vault but this device already had one,
  /// which restore deliberately leaves in place (decision Q4/Q2: keep the
  /// vault). Its loans still point at the OLD library's book ids, which the
  /// restored library may not contain — and restore cannot check them (the
  /// kept vault is encrypted under a passphrase restore never sees). The UI
  /// must say so instead of claiming integrity (review 2026-09-03).
  final bool existingVaultKept;

  /// True when every restored loan references an existing book and borrower
  /// AND no unchecked vault was carried over. When [existingVaultKept] is
  /// true integrity is UNKNOWN, so this is false.
  bool get isIntact => danglingLoans.isEmpty && !existingVaultKept;
}
