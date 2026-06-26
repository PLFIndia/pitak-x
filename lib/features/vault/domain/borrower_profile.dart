/// Borrower profile + stats computation (domain, pure Dart, AGENTS.md §3.1).
///
/// Port of Kotlin `GetBorrowerProfileUseCase` (D31) + `LoanRepositoryImpl.
/// statsFor`. Kotlin computes the stats with one SQL aggregation over the
/// encrypted `loans` table; here the loans are already decrypted in the session
/// (`VaultData`), so we compute the identical numbers in Dart over the
/// in-memory list. Pure and side-effect-free, so it is trivially testable.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// A borrower with their active + returned loans and live-computed stats.
class BorrowerProfile {
  /// Creates a profile snapshot.
  const BorrowerProfile({
    required this.borrower,
    required this.active,
    required this.returned,
    required this.stats,
  });

  /// The borrower.
  final Borrower borrower;

  /// Loans not yet returned, ordered like Kotlin `observeActive`: due date
  /// ascending (nulls last), then most-recently-lent, then id descending.
  final List<Loan> active;

  /// Returned loans, most-recently-returned first.
  final List<Loan> returned;

  /// Aggregated statistics.
  final BorrowerStats stats;
}

/// Builds a [BorrowerProfile] for [borrower] from [allLoans] (that borrower's
/// loans) at time [now] (epoch millis).
///
/// [allLoans] should already be filtered to this borrower; any loan whose
/// `borrowerId` differs is ignored defensively.
BorrowerProfile buildBorrowerProfile({
  required Borrower borrower,
  required List<Loan> allLoans,
  required int now,
}) {
  final mine = allLoans.where((l) => l.borrowerId == borrower.id).toList();

  final active = mine.where((l) => !l.isReturned).toList()..sort(_activeOrder);
  final returned = mine.where((l) => l.isReturned).toList()
    ..sort((a, b) => (b.returnedDate ?? 0).compareTo(a.returnedDate ?? 0));

  return BorrowerProfile(
    borrower: borrower,
    active: active,
    returned: returned,
    stats: _statsFor(mine, now),
  );
}

/// Active-loan ordering (Kotlin `observeActive`): due date ascending with nulls
/// last, then most-recently-lent first, then id descending.
int _activeOrder(Loan a, Loan b) {
  final aHasDue = a.dueDate != null;
  final bHasDue = b.dueDate != null;
  if (aHasDue != bHasDue) return aHasDue ? -1 : 1; // nulls last
  if (aHasDue && bHasDue) {
    final byDue = a.dueDate!.compareTo(b.dueDate!);
    if (byDue != 0) return byDue;
  }
  final byLent = b.lentDate.compareTo(a.lentDate); // most-recent first
  if (byLent != 0) return byLent;
  return b.id.compareTo(a.id);
}

/// Mirrors Kotlin `statsForBorrower` + `statsFor`:
///  - totalLoans = count
///  - averageReturnDays = mean (returned_date - lent_date) over returned loans,
///    in days; null when nothing returned
///  - overdueRate = overdueCount / totalLoans (0 when no loans). A loan is
///    overdue if it has a due date and either it's still out past [now], or it
///    was returned after its due date.
BorrowerStats _statsFor(List<Loan> loans, int now) {
  if (loans.isEmpty) {
    return const BorrowerStats(
      totalLoans: 0,
      averageReturnDays: null,
      overdueRate: 0,
    );
  }
  var returnedCount = 0;
  var totalReturnedDurationMs = 0;
  var overdueCount = 0;
  for (final l in loans) {
    final returnedAt = l.returnedDate;
    if (returnedAt != null) {
      returnedCount++;
      totalReturnedDurationMs += returnedAt - l.lentDate;
    }
    final due = l.dueDate;
    if (due != null) {
      final overdue = returnedAt == null ? now > due : returnedAt > due;
      if (overdue) overdueCount++;
    }
  }
  final avgDays = returnedCount > 0
      ? (totalReturnedDurationMs / returnedCount) / (1000.0 * 60 * 60 * 24)
      : null;
  return BorrowerStats(
    totalLoans: loans.length,
    averageReturnDays: avgDays,
    overdueRate: overdueCount / loans.length,
  );
}
