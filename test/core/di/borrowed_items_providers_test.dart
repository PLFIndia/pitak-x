import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

import '../../features/periodicals/application/periodical_fakes.dart';
import '../../support/quiet_series_list.dart';

class _Session extends VaultSessionController {
  _Session(this._initial);
  final VaultSessionState _initial;

  @override
  Future<VaultSessionState> build() async => _initial;

  void show(VaultSessionState next) {
    state = AsyncData(next);
  }

  void showLoadingWithPrevious() {
    state = const AsyncLoading<VaultSessionState>().copyWithPrevious(state);
  }

  void showErrorWithPrevious() {
    state = AsyncError<VaultSessionState>(
      StateError('session unavailable'),
      StackTrace.current,
    ).copyWithPrevious(state);
  }
}

ProviderContainer _container({
  required _Session session,
  required FakeItems items,
  FakePeriodicals? periodicals,
  int Function()? clock,
  List<Override> extraOverrides = const [],
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
      ...extraOverrides,
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
    'loading/error with a previous unlock returns null without reads',
    () async {
      final items = FakeItems();
      final stored = items.seed(const CatalogueItem(title: 'Current title'));
      final session = _Session(
        VaultUnlocked(
          VaultData(
            borrowers: const [Borrower(id: 1, name: 'Asha')],
            loans: [Loan(id: 9, itemId: stored.id, borrowerId: 1, lentDate: 0)],
          ),
        ),
      );
      final container = _container(session: session, items: items);
      expect(
        (await container.read(borrowedItemsSnapshotProvider.future))!.entries,
        hasLength(1),
      );
      final reads = items.calls.length;

      session.showLoadingWithPrevious();
      expect(
        await container.read(borrowedItemsSnapshotProvider.future),
        isNull,
      );
      expect(items.calls.length, reads);

      session.showErrorWithPrevious();
      expect(
        await container.read(borrowedItemsSnapshotProvider.future),
        isNull,
      );
      expect(items.calls.length, reads);
    },
  );

  // Review finding P3-M4 (ADR 0031): the snapshot used to be made again
  // whenever the Library list changed its state, also by scrolling.
  test('the Library list loading a page and a search do not make the '
      'snapshot again; "catalogue changed" does', () async {
    final items = FakeItems();
    final stored = items.seed(const CatalogueItem(title: 'Old title'));
    for (var i = 2; i <= 150; i++) {
      items.seed(CatalogueItem(title: 'Book $i'));
    }
    final session = _Session(
      VaultUnlocked(
        VaultData(
          borrowers: const [Borrower(id: 1, name: 'Asha')],
          loans: [Loan(id: 9, itemId: stored.id, borrowerId: 1, lentDate: 0)],
        ),
      ),
    );
    final container = _container(
      session: session,
      items: items,
      // A Magazines list that hears nothing: the snapshot listens to that
      // list too, and would otherwise hear "changed" through it.
      extraOverrides: [
        periodicalsControllerProvider.overrideWith(QuietSeriesList.new),
      ],
    );
    final list = container.listen(libraryControllerProvider, (_, _) {});
    addTearDown(list.close);
    await container.read(libraryControllerProvider.future);
    await container.read(borrowedItemsSnapshotProvider.future);
    await container.pump();
    final callsBefore = items.calls.length;

    final notifier = container.read(libraryControllerProvider.notifier);
    await notifier.loadMore();
    notifier.onQueryChanged('Book 1');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await container.read(libraryControllerProvider.future);
    await container.pump();
    await container.read(borrowedItemsSnapshotProvider.future);
    expect(
      items.calls.sublist(callsBefore),
      ['page', 'page'],
      reason: "the list's own two reads, and no read for the snapshot",
    );

    items.rows[stored.id] = stored.copyWith(title: 'New title');
    container.read(catalogueChangesProvider.notifier).changed();
    final after = await container.read(borrowedItemsSnapshotProvider.future);
    expect(after!.entries.single.item.title, 'New title');
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
      container.read(catalogueChangesProvider.notifier).changed();
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
