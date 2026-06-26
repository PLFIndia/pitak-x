import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

void main() {
  const borrower = Borrower(id: 1, name: 'Asha');
  const day = 1000 * 60 * 60 * 24;

  Loan loan({
    int borrowerId = 1,
    int bookId = 1,
    int lentDate = 0,
    int? dueDate,
    int? returnedDate,
    int id = 0,
  }) => Loan(
    id: id,
    bookId: bookId,
    borrowerId: borrowerId,
    lentDate: lentDate,
    dueDate: dueDate,
    returnedDate: returnedDate,
  );

  test('empty loans → zero stats, empty lists', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: const [],
      now: 0,
    );
    expect(p.stats.totalLoans, 0);
    expect(p.stats.averageReturnDays, isNull);
    expect(p.stats.overdueRate, 0);
    expect(p.active, isEmpty);
    expect(p.returned, isEmpty);
  });

  test('ignores loans for other borrowers', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [loan(borrowerId: 2, id: 9)],
      now: 0,
    );
    expect(p.stats.totalLoans, 0);
  });

  test('splits active vs returned', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [
        loan(id: 1),
        loan(id: 2, returnedDate: day),
      ],
      now: 2 * day,
    );
    expect(p.active.map((l) => l.id), [1]);
    expect(p.returned.map((l) => l.id), [2]);
    expect(p.stats.totalLoans, 2);
  });

  test('averageReturnDays = mean of (returned - lent) over returned loans', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [
        loan(id: 1, returnedDate: 2 * day), // lent at 0 → 2 days
        loan(id: 2, returnedDate: 4 * day), // lent at 0 → 4 days
        loan(id: 3), // still out, excluded from avg
      ],
      now: 10 * day,
    );
    expect(p.stats.averageReturnDays, closeTo(3, 1e-9)); // (2+4)/2
  });

  test('overdueRate counts out-past-due and returned-late over total', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [
        loan(id: 1, dueDate: day, returnedDate: 2 * day), // returned late
        loan(id: 2, dueDate: 5 * day), // still out, now=3d → not overdue
        loan(id: 3, dueDate: day), // still out, now=3d → overdue
        loan(id: 4), // no due date → never overdue
      ],
      now: 3 * day,
    );
    // overdue = loan1 (late) + loan3 (out past due) = 2 of 4
    expect(p.stats.overdueRate, closeTo(0.5, 1e-9));
    expect(p.stats.totalLoans, 4);
  });

  test('active ordering: due-date asc, nulls last, then recent lent', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [
        loan(id: 1, lentDate: day), // no due date → last
        loan(id: 2, dueDate: 5 * day),
        loan(id: 3, dueDate: 2 * day),
      ],
      now: 0,
    );
    expect(p.active.map((l) => l.id), [3, 2, 1]);
  });

  test('returned history is most-recently-returned first', () {
    final p = buildBorrowerProfile(
      borrower: borrower,
      allLoans: [
        loan(id: 1, returnedDate: day),
        loan(id: 2, returnedDate: 5 * day),
        loan(id: 3, returnedDate: 2 * day),
      ],
      now: 10 * day,
    );
    expect(p.returned.map((l) => l.id), [2, 3, 1]);
  });
}
