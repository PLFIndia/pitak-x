import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/delete_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_actions.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import '../periodicals/application/periodical_fakes.dart';

/// Item store whose hard delete also updates the series-side issue fixture,
/// matching the single real catalogue that production repositories share.
class _DeleteItems extends FakeItems {
  _DeleteItems(this.periodicals);

  final FakePeriodicals periodicals;
  Failure? deleteFailure;

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    final failure = deleteFailure;
    if (failure != null) return left(failure);
    rows.remove(id);
    for (final issues in periodicals.issues.values) {
      issues.removeWhere((item) => item.id == id);
    }
    return right(unit);
  }
}

class _NoVault implements VaultLoanPurger {
  @override
  bool get vaultExists => false;

  @override
  bool get isUnlocked => false;

  @override
  bool hasLoansForBook(int bookId) => false;

  @override
  Future<Either<Failure, Unit>> purgeLoansForBook(int bookId) async =>
      right(unit);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Route/dialog transitions and the delete future need only a few frames.
  // Keep this regression bounded so a broken animation cannot hang the suite.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('S9: issue hard-delete refreshes kept-alive Magazines through '
      'the real delete action', (tester) async {
    final periodicals = FakePeriodicals();
    final series = periodicals.seed(const Periodical(title: 'Frontline'));
    final items = _DeleteItems(periodicals);
    final issue = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        details: IssueOf(
          periodicalUid: series.periodicalUid!,
          issueNumber: 5,
          issueDate: DateTime.utc(2026, 10).millisecondsSinceEpoch,
        ),
      ),
    );
    periodicals.issues[series.periodicalUid!] = [issue];

    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        deleteCatalogueItemUseCaseProvider.overrideWith(
          (ref) async =>
              DeleteCatalogueItemUseCase(books: items, vault: _NoVault()),
        ),
        nowTickProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    final librarySub = container.listen(libraryControllerProvider, (_, _) {});
    addTearDown(librarySub.close);
    var periodicalEvents = 0;
    final periodicalSub = container.listen(
      periodicalsControllerProvider,
      (_, _) => periodicalEvents++,
      fireImmediately: true,
    );
    addTearDown(periodicalSub.close);

    await container.read(libraryControllerProvider.future);
    final before = await container.read(periodicalsControllerProvider.future);
    final notifier = container.read(periodicalsControllerProvider.notifier);
    expect(before.single.issueCount, 1);
    final baseline = periodicalEvents;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Item')),
                        body: DeleteForeverButton(book: issue),
                      ),
                    ),
                  ),
                  child: const Text('open detail'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open detail'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Delete permanently'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Delete'));
    await _pumpFrames(tester);

    expect(items.rows, isEmpty, reason: 'the issue was really hard-deleted');
    expect(find.text('open detail'), findsOneWidget);
    await tester.pump();
    final after = await container.read(periodicalsControllerProvider.future);
    expect(periodicalEvents, greaterThan(baseline));
    expect(after.single.issueCount, 0);
    expect(after.single.latestIssueDate, isNull);
    expect(
      identical(
        notifier,
        container.read(periodicalsControllerProvider.notifier),
      ),
      isTrue,
      reason: 'the Magazines route/provider stayed alive throughout',
    );
  });

  testWidgets('S9: a failed hard delete uses neutral safe error copy', (
    tester,
  ) async {
    final periodicals = FakePeriodicals();
    final items = _DeleteItems(periodicals)
      ..deleteFailure = const StorageFailure('private database detail');
    final item = items.seed(
      const CatalogueItem(title: 'Chess set', details: OtherItemOf()),
    );
    final container = ProviderContainer(
      overrides: [
        deleteCatalogueItemUseCaseProvider.overrideWith(
          (ref) async =>
              DeleteCatalogueItemUseCase(books: items, vault: _NoVault()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: DeleteForeverButton(book: item)),
        ),
      ),
    );
    await tester.tap(find.text('Delete permanently'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Delete'));
    await _pumpFrames(tester);

    expect(find.text('Could not delete this item.'), findsOneWidget);
    expect(find.textContaining('book'), findsNothing);
    expect(find.textContaining('private database detail'), findsNothing);
    expect(items.rows, hasLength(1), reason: 'a failed delete changes nothing');
  });
}
