/// Read models for the vault-gated Borrowed Items screen (pure Dart).
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

/// One complete, actionable active-loan row.
final class BorrowedLoan {
  /// Creates a row. [coverUrl] is the exact reference shown and shared.
  const BorrowedLoan({
    required this.item,
    required this.loan,
    required this.borrower,
    required this.urgency,
    required this.coverUrl,
  });

  /// Catalogue row, including a soft-removed row with an active loan.
  final CatalogueItem item;

  /// Active loan; identity for cards and per-card busy state is [Loan.id].
  final Loan loan;

  /// Resolved borrower.
  final Borrower borrower;

  /// Status at the snapshot's injected time.
  final LoanUrgency urgency;

  /// Own cover, or a magazine issue's series-cover fallback.
  final String? coverUrl;
}

/// Ordered active-loan rows plus references that cannot safely be shown.
final class BorrowedItemsSnapshot {
  /// Creates a snapshot.
  const BorrowedItemsSnapshot({
    required this.entries,
    required this.unresolvedCount,
  });

  /// An empty snapshot with no active loans.
  static const empty = BorrowedItemsSnapshot(entries: [], unresolvedCount: 0);

  /// Due-date ascending (nulls last), then title, borrower and loan id.
  final List<BorrowedLoan> entries;

  /// Active loans whose catalogue item or borrower reference is missing.
  final int unresolvedCount;

  /// True when at least one active loan exists, even if none can be shown.
  bool get hasActiveLoans => entries.isNotEmpty || unresolvedCount > 0;
}
