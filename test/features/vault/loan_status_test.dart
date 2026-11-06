import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

void main() {
  const now = 1000000000000;
  const hour = 60 * 60 * 1000;
  Loan loan(int? due, {int? returned}) => Loan(
    id: 1,
    itemId: 2,
    borrowerId: 3,
    lentDate: 0,
    dueDate: due,
    returnedDate: returned,
  );

  test('no due date is open-ended', () {
    expect(loanUrgency(loan(null), now), LoanUrgency.noDueDate);
  });

  test('due exactly now and exactly 72 hours ahead are due soon', () {
    expect(loanUrgency(loan(now), now), LoanUrgency.dueSoon);
    expect(
      loanUrgency(loan(now + kLoanDueSoonWindowMillis), now),
      LoanUrgency.dueSoon,
    );
  });

  test('one millisecond past due is overdue', () {
    expect(loanUrgency(loan(now - 1), now), LoanUrgency.overdue);
  });

  test('beyond 72 hours is due later', () {
    expect(
      loanUrgency(loan(now + kLoanDueSoonWindowMillis + 1), now),
      LoanUrgency.dueLater,
    );
  });

  test('window is fixed milliseconds across a DST transition', () {
    // 2026-11-01 00:00 local in America/New_York is followed by a 25-hour day.
    // The classifier must still use 72 elapsed hours, never calendar fields.
    final start = DateTime(2026, 10, 31).millisecondsSinceEpoch;
    final due = start + kLoanDueSoonWindowMillis;
    expect(loanUrgency(loan(due), start), LoanUrgency.dueSoon);
    expect(loanUrgency(loan(due + 1), start), LoanUrgency.dueLater);
  });

  test('custom window preserves Pending behavior', () {
    expect(
      loanUrgency(
        loan(now + 5 * 24 * hour),
        now,
        dueSoonWithinMillis: 7 * 24 * hour,
      ),
      LoanUrgency.dueSoon,
    );
  });

  test('formatLoanDate uses local fields, including local midnight', () {
    final localMidnight = DateTime(2026, 11, 6);
    expect(
      formatLoanDate(localMidnight.millisecondsSinceEpoch),
      '6 November 2026',
    );
  });
}
