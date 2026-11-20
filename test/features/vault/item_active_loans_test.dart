/// Which loans the item's page shows for one item, and in which order
/// (review finding P4-M3; D103, D104).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/item_active_loans.dart';

const _asha = Borrower(id: 1, name: 'Asha');
const _ravi = Borrower(id: 2, name: 'Ravi');

Loan _loan(
  int id, {
  int itemId = 7,
  int borrowerId = 1,
  int? due,
  int? returned,
}) => Loan(
  id: id,
  itemId: itemId,
  borrowerId: borrowerId,
  lentDate: 100,
  dueDate: due,
  returnedDate: returned,
);

List<int> _ids(List<ActiveItemLoan> loans) => [
  for (final entry in loans) entry.loan.id,
];

void main() {
  test('an empty vault has no loan of the item', () {
    expect(activeLoansOfItem(itemId: 7, data: VaultData.empty), isEmpty);
  });

  test('only the loans of THIS item, and only those that are still out', () {
    final data = VaultData(
      borrowers: const [_asha, _ravi],
      loans: [
        _loan(1),
        _loan(2, itemId: 8),
        _loan(3, returned: 500),
        _loan(4, borrowerId: 2),
      ],
    );

    expect(_ids(activeLoansOfItem(itemId: 7, data: data)), [1, 4]);
    expect(_ids(activeLoansOfItem(itemId: 8, data: data)), [2]);
    expect(activeLoansOfItem(itemId: 9, data: data), isEmpty);
  });

  test('ordered by due date, a loan without one last, then by loan id', () {
    final data = VaultData(
      borrowers: const [_asha],
      loans: [
        _loan(5),
        _loan(4, due: 3000),
        _loan(3),
        _loan(2, due: 1000),
        _loan(1, due: 3000),
      ],
    );

    expect(_ids(activeLoansOfItem(itemId: 7, data: data)), [2, 1, 4, 3, 5]);
  });

  test('each loan comes with its borrower', () {
    final data = VaultData(
      borrowers: const [_asha, _ravi],
      loans: [_loan(1, borrowerId: 2, due: 1000), _loan(2, due: 2000)],
    );

    final loans = activeLoansOfItem(itemId: 7, data: data);

    expect(loans[0].borrower, same(_ravi));
    expect(loans[1].borrower, same(_asha));
  });

  test('two copies with the same borrower are two loans', () {
    final data = VaultData(
      borrowers: const [_asha],
      loans: [_loan(1), _loan(2)],
    );

    final loans = activeLoansOfItem(itemId: 7, data: data);

    expect(_ids(loans), [1, 2]);
    expect(loans.every((entry) => entry.borrower == _asha), isTrue);
  });

  test('a loan whose borrower the vault does not hold is still listed, '
      'without a borrower', () {
    final data = VaultData(
      borrowers: const [_asha],
      loans: [_loan(1, borrowerId: 99)],
    );

    final loans = activeLoansOfItem(itemId: 7, data: data);

    expect(_ids(loans), [1]);
    expect(loans.single.borrower, isNull);
  });

  test("the vault's own list of loans is not reordered", () {
    final stored = [_loan(2), _loan(1, due: 1000)];
    final data = VaultData(borrowers: const [_asha], loans: stored);

    activeLoansOfItem(itemId: 7, data: data);

    expect([for (final loan in stored) loan.id], [2, 1]);
  });
}
