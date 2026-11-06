/// Shared status and display-date rules for active loans (pure Dart).
library;

import 'package:pitaka/core/text/display_date.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Fixed rolling 72-hour due-soon window, not three calendar days.
const int kLoanDueSoonWindowMillis = 72 * 60 * 60 * 1000;

/// Time-dependent state of an active loan.
enum LoanUrgency {
  /// The due instant has passed.
  overdue,

  /// Due now or within the rolling 72-hour window.
  dueSoon,

  /// Dated, but beyond the due-soon window.
  dueLater,

  /// Open-ended loan.
  noDueDate,
}

/// Classifies [loan] at epoch-millisecond [now].
///
/// Callers deliberately exclude returned loans before calling this. Overdue
/// uses [Loan.isOverdue], the existing single source of truth (`now > due`).
/// A loan due exactly now is due soon, not overdue.
LoanUrgency loanUrgency(
  Loan loan,
  int now, {
  int dueSoonWithinMillis = kLoanDueSoonWindowMillis,
}) {
  final due = loan.dueDate;
  if (due == null) return LoanUrgency.noDueDate;
  if (loan.isOverdue(now)) return LoanUrgency.overdue;
  return due <= now + dueSoonWithinMillis
      ? LoanUrgency.dueSoon
      : LoanUrgency.dueLater;
}

/// Formats a valid local loan instant, or returns null for unset or
/// out-of-range stored values instead of throwing.
String? formatLoanDateOrNull(int? epochMillis) =>
    formatDisplayDateOrNull(epochMillis);
