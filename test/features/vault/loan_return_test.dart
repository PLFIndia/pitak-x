/// The rule for taking a return back, and the one new method of `Loan`
/// (review finding P4-M3, D107).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';

void main() {
  group('Loan.reopened', () {
    test('clears the date of return and keeps every other field', () {
      const returned = Loan(
        id: 4,
        itemId: 7,
        borrowerId: 2,
        lentDate: 100,
        dueDate: 500,
        returnedDate: 300,
        notes: 'a note',
      );

      final open = returned.reopened();

      expect(open.isReturned, isFalse);
      expect(open.returnedDate, isNull);
      expect(open.id, 4);
      expect(open.itemId, 7);
      expect(open.borrowerId, 2);
      expect(open.lentDate, 100, reason: 'the first loan keeps its dates');
      expect(open.dueDate, 500);
      expect(open.notes, 'a note');
    });

    test('a loan that is still out stays as it is', () {
      const out = Loan(id: 4, itemId: 7, borrowerId: 2, lentDate: 100);

      final same = out.reopened();

      expect(same.isReturned, isFalse);
      expect(same.id, 4);
      expect(same.lentDate, 100);
    });

    test('copyWith still cannot clear the date: reopened() is the way', () {
      const returned = Loan(
        id: 4,
        itemId: 7,
        borrowerId: 2,
        lentDate: 100,
        returnedDate: 300,
      );

      // Written down so that nobody "fixes" an Undo with copyWith(null).
      expect(returned.copyWith().returnedDate, 300);
    });
  });

  group('ReopenDecision.forLoan', () {
    // The loan whose return is taken back: item 7, returned.
    const mine = Loan(
      id: 1,
      itemId: 7,
      borrowerId: 2,
      lentDate: 100,
      returnedDate: 300,
    );
    Loan other({required int id, int itemId = 7, int? returnedDate}) => Loan(
      id: id,
      itemId: itemId,
      borrowerId: 9,
      lentDate: 200,
      returnedDate: returnedDate,
    );

    test('one copy, nobody else has it: allowed', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: const [mine],
      );

      expect(decision, isA<ReopenAllowed>());
      expect(decision.reason, isNull);
    });

    test('one copy, lent again in the meantime: refused, with a sentence', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: [mine, other(id: 2)],
      );

      expect(decision, isA<ReopenRefusedNoCopyFree>());
      expect(decision.reason, reopenRefusedNoCopyFreeMessage);
      // A plain sentence for the user: no number, no name, no code.
      expect(decision.reason, isNot(contains('7')));
      expect(decision.reason, endsWith('.'));
    });

    test('three copies, two others out: allowed (one copy is free)', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 3,
        loans: [mine, other(id: 2), other(id: 3)],
      );

      expect(decision, isA<ReopenAllowed>());
    });

    test('three copies, three others out: refused', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 3,
        loans: [mine, other(id: 2), other(id: 3), other(id: 4)],
      );

      expect(decision, isA<ReopenRefusedNoCopyFree>());
    });

    test('loans of the same item that came back do not count', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: [mine, other(id: 2, returnedDate: 250)],
      );

      expect(decision, isA<ReopenAllowed>());
    });

    test('loans of other items do not count', () {
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: [mine, other(id: 2, itemId: 8), other(id: 3, itemId: 9)],
      );

      expect(decision, isA<ReopenAllowed>());
    });

    test('a copy count of zero or less counts as one copy', () {
      for (final copies in [0, -3]) {
        expect(
          ReopenDecision.forLoan(
            loan: mine,
            copyCount: copies,
            loans: const [mine],
          ),
          isA<ReopenAllowed>(),
          reason: 'copies: $copies, nobody else has it',
        );
        expect(
          ReopenDecision.forLoan(
            loan: mine,
            copyCount: copies,
            loans: [mine, other(id: 2)],
          ),
          isA<ReopenRefusedNoCopyFree>(),
          reason: 'copies: $copies, lent again',
        );
      }
    });

    test('the loan itself never counts against itself, whatever state the '
        'list shows it in', () {
      // The list may hold the loan as returned (the usual case) or, read a
      // moment too early, as still out. Neither may block its own Undo.
      const stillOut = Loan(id: 1, itemId: 7, borrowerId: 2, lentDate: 100);

      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: const [stillOut],
      );

      expect(decision, isA<ReopenAllowed>());
    });

    test('the rule does not look at who borrows: the borrower limit is for '
        'new loans (D107)', () {
      // Five other loans of the SAME borrower, of other items.
      final decision = ReopenDecision.forLoan(
        loan: mine,
        copyCount: 1,
        loans: [
          mine,
          for (var i = 10; i < 15; i++)
            Loan(id: i, itemId: i, borrowerId: 2, lentDate: 1),
        ],
      );

      expect(decision, isA<ReopenAllowed>());
    });
  });
}
