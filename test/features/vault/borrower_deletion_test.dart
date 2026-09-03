import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/borrower_deletion.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

void main() {
  Loan loan({required int borrowerId, int? returnedDate}) => Loan(
    bookId: 1,
    borrowerId: borrowerId,
    lentDate: 1,
    returnedDate: returnedDate,
  );

  test('no loans at all → allowed with zero history', () {
    final plan = BorrowerDeletion.plan(borrowerId: 1, loans: const []);
    expect(plan, isA<BorrowerDeletionAllowed>());
    expect((plan as BorrowerDeletionAllowed).returnedLoanCount, 0);
  });

  test('only returned loans → allowed, counts the history rows', () {
    final plan = BorrowerDeletion.plan(
      borrowerId: 1,
      loans: [
        loan(borrowerId: 1, returnedDate: 2),
        loan(borrowerId: 1, returnedDate: 3),
        loan(borrowerId: 1, returnedDate: 4),
      ],
    );
    expect(plan, isA<BorrowerDeletionAllowed>());
    expect((plan as BorrowerDeletionAllowed).returnedLoanCount, 3);
  });

  test('a single active loan blocks, even amid returned history', () {
    final plan = BorrowerDeletion.plan(
      borrowerId: 1,
      loans: [
        loan(borrowerId: 1, returnedDate: 2),
        loan(borrowerId: 1), // still out
        loan(borrowerId: 1, returnedDate: 3),
      ],
    );
    expect(plan, isA<BorrowerDeletionBlocked>());
    expect((plan as BorrowerDeletionBlocked).activeLoanCount, 1);
  });

  test("other borrowers' loans are ignored", () {
    final plan = BorrowerDeletion.plan(
      borrowerId: 1,
      loans: [
        loan(borrowerId: 2), // someone else's active loan
        loan(borrowerId: 2, returnedDate: 9),
        loan(borrowerId: 1, returnedDate: 5),
      ],
    );
    expect(plan, isA<BorrowerDeletionAllowed>());
    expect((plan as BorrowerDeletionAllowed).returnedLoanCount, 1);
  });

  test('the blocked message is a sentence, not a SQL diagnostic', () {
    expect(activeLoansBlockDeleteMessage, isNot(contains('FOREIGN KEY')));
    expect(activeLoansBlockDeleteMessage, endsWith('.'));
  });
}
