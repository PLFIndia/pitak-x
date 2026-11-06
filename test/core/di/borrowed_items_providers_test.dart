import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

import '../../features/periodicals/application/periodical_fakes.dart';

class _Session extends VaultSessionController {
  _Session(this._initial);
  final VaultSessionState _initial;

  @override
  Future<VaultSessionState> build() async => _initial;

  void show(VaultSessionState next) {
    state = AsyncData(next);
  }
}

ProviderContainer _container({
  required _Session session,
  required FakeItems items,
  FakePeriodicals? periodicals,
  int Function()? clock,
}) {
  final container = ProviderContainer(
    overrides: [
      vaultSessionControllerProvider.overrideWith(() => session),
      catalogueItemRepositoryProvider.overrideWith((ref) async => items),
      periodicalRepositoryProvider.overrideWith(
        (ref) async => periodicals ?? FakePeriodicals(),
      ),
      settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
      if (clock != null) clockProvider.overrideWithValue(clock),
      if (clock != null) nowTickProvider.overrideWith((ref) => clock()),
    ],
  );
  final sub = container.listen(borrowedItemsSnapshotProvider, (_, _) {});
  addTearDown(sub.close);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('locked and no-active-loan states perform no catalogue read', () async {
    final lockedItems = FakeItems();
    final locked = _container(
      session: _Session(const VaultLocked()),
      items: lockedItems,
    );
    expect(await locked.read(borrowedItemsSnapshotProvider.future), isNull);
    expect(lockedItems.calls, isEmpty);

    final emptyItems = FakeItems();
    final empty = _container(
      session: _Session(const VaultUnlocked(VaultData.empty)),
      items: emptyItems,
    );
    final snapshot = await empty.read(borrowedItemsSnapshotProvider.future);
    expect(snapshot!.hasActiveLoans, isFalse);
    expect(emptyItems.calls, isEmpty);
  });

  test(
    'minute ticks, catalogue signals and returned loans refresh the snapshot',
    () async {
      var now = 10000;
      final items = FakeItems();
      final stored = items.seed(const CatalogueItem(title: 'Old title'));
      final loan = Loan(
        id: 9,
        itemId: stored.id,
        borrowerId: 1,
        lentDate: 0,
        dueDate: 11000,
      );
      final session = _Session(
        VaultUnlocked(
          VaultData(
            borrowers: const [Borrower(id: 1, name: 'Asha')],
            loans: [loan],
          ),
        ),
      );
      final container = _container(
        session: session,
        items: items,
        clock: () => now,
      );
      final sub = container.listen(borrowedItemsSnapshotProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await container.read(borrowedItemsSnapshotProvider.future);
      expect(first!.entries.single.urgency, LoanUrgency.dueSoon);

      now = 12000;
      container.invalidate(nowTickProvider);
      final second = await container.read(borrowedItemsSnapshotProvider.future);
      expect(second!.entries.single.urgency, LoanUrgency.overdue);

      items.rows[stored.id] = stored.copyWith(title: 'New title');
      container.invalidate(libraryControllerProvider);
      final third = await container.read(borrowedItemsSnapshotProvider.future);
      expect(third!.entries.single.item.title, 'New title');

      session.show(
        VaultUnlocked(
          VaultData(
            borrowers: const [Borrower(id: 1, name: 'Asha')],
            loans: [loan.copyWith(returnedDate: now)],
          ),
        ),
      );
      final fourth = await container.read(borrowedItemsSnapshotProvider.future);
      expect(fourth!.hasActiveLoans, isFalse);
    },
  );

  test(
    'repository failure remains an error, never an empty snapshot',
    () async {
      const failure = StorageFailure('private');
      final items = FakeItems()..getByIdFailure = failure;
      final session = _Session(
        const VaultUnlocked(
          VaultData(
            borrowers: [Borrower(id: 1, name: 'Asha')],
            loans: [Loan(id: 9, itemId: 1, borrowerId: 1, lentDate: 0)],
          ),
        ),
      );
      final container = _container(session: session, items: items);
      await expectLater(
        container.read(borrowedItemsSnapshotProvider.future),
        throwsA(same(failure)),
      );
    },
  );
}
