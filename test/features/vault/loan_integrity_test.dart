import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';

void main() {
  const loanOk = Loan(bookId: 1, borrowerId: 10, lentDate: 1);
  const loanBadBook = Loan(bookId: 99, borrowerId: 10, lentDate: 1);
  const loanBadBorrower = Loan(bookId: 1, borrowerId: 99, lentDate: 1);

  group('LoanIntegrity', () {
    test('intact when every reference resolves', () {
      expect(
        LoanIntegrity.isIntact(
          loans: const [loanOk],
          knownBookIds: {1, 2},
          knownBorrowerIds: {10},
        ),
        isTrue,
      );
    });

    test('flags a loan pointing at a missing book', () {
      final dangling = LoanIntegrity.findDangling(
        loans: const [loanBadBook],
        knownBookIds: {1},
        knownBorrowerIds: {10},
      );
      expect(dangling.length, 1);
      expect(dangling.single.missingBook, isTrue);
      expect(dangling.single.missingBorrower, isFalse);
    });

    test('flags a loan pointing at a missing borrower', () {
      final dangling = LoanIntegrity.findDangling(
        loans: const [loanBadBorrower],
        knownBookIds: {1},
        knownBorrowerIds: {10},
      );
      expect(dangling.single.missingBorrower, isTrue);
      expect(dangling.single.missingBook, isFalse);
    });

    test('reports both when book and borrower are missing', () {
      final dangling = LoanIntegrity.findDangling(
        loans: const [Loan(bookId: 99, borrowerId: 99, lentDate: 1)],
        knownBookIds: {1},
        knownBorrowerIds: {10},
      );
      expect(dangling.single.missingBook, isTrue);
      expect(dangling.single.missingBorrower, isTrue);
    });

    test('empty loans are trivially intact', () {
      expect(
        LoanIntegrity.isIntact(
          loans: const [],
          knownBookIds: const {},
          knownBorrowerIds: const {},
        ),
        isTrue,
      );
    });
  });
}
