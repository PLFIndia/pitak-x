import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

void main() {
  BorrowerLimitPolicy valid(int? limit, BorrowerLimitAction action) =>
      BorrowerLimitPolicy.validate(
        maxActiveLoans: limit,
        action: action,
      ).toNullable()!;

  group('BorrowerLimitPolicy.validate', () {
    test('accepts off and both inclusive boundaries', () {
      expect(valid(null, BorrowerLimitAction.warn).isOn, isFalse);
      expect(valid(1, BorrowerLimitAction.warn).maxActiveLoans, 1);
      expect(valid(99, BorrowerLimitAction.refuse).maxActiveLoans, 99);
    });

    test('rejects negative, zero and above-maximum limits', () {
      for (final limit in [-1, 0, 100]) {
        expect(
          BorrowerLimitPolicy.validate(
            maxActiveLoans: limit,
            action: BorrowerLimitAction.warn,
          ).isLeft(),
          isTrue,
          reason: '$limit',
        );
      }
    });
  });

  group('BorrowerLimitPolicy.check', () {
    test('off and under-limit loans are allowed', () {
      expect(
        valid(null, BorrowerLimitAction.refuse).check(activeLoans: 99),
        BorrowerLimitCheck.allowed,
      );
      expect(
        valid(3, BorrowerLimitAction.refuse).check(activeLoans: 2),
        BorrowerLimitCheck.allowed,
      );
    });

    test('Warn needs confirmation at and over the limit', () {
      final policy = valid(3, BorrowerLimitAction.warn);
      expect(
        policy.check(activeLoans: 3),
        BorrowerLimitCheck.needsConfirmation,
      );
      expect(
        policy.check(activeLoans: 4),
        BorrowerLimitCheck.needsConfirmation,
      );
      expect(
        policy.check(activeLoans: 4, warningAcknowledged: true),
        BorrowerLimitCheck.allowed,
      );
    });

    test('Refuse rejects at and over the limit even when acknowledged', () {
      final policy = valid(3, BorrowerLimitAction.refuse);
      for (final active in [3, 4]) {
        expect(
          policy.check(activeLoans: active, warningAcknowledged: true),
          BorrowerLimitCheck.refused,
        );
      }
    });
  });

  test('activeLoanCountForBorrower ignores returned and other borrowers', () {
    final loans = [
      const Loan(itemId: 1, borrowerId: 7, lentDate: 1),
      const Loan(itemId: 1, borrowerId: 7, lentDate: 2),
      const Loan(itemId: 2, borrowerId: 7, lentDate: 3, returnedDate: 4),
      const Loan(itemId: 3, borrowerId: 8, lentDate: 5),
    ];
    expect(activeLoanCountForBorrower(loans, 7), 2);
    expect(activeLoanCountForBorrower(loans, 8), 1);
    expect(activeLoanCountForBorrower(loans, 9), 0);
  });

  test('shared refusal copy names both numbers and handles singular', () {
    expect(
      borrowerLimitRefusalMessage(activeLoans: 1, limit: 1),
      'This borrower has 1 item out; your limit is 1. '
      'Mark one returned before lending another.',
    );
    expect(
      borrowerLimitRefusalMessage(activeLoans: 4, limit: 3),
      contains('4 items out; your limit is 3'),
    );
  });
}
