/// S14 tests for the Library add sheet (`widgets/add_sheet.dart`): the FAB
/// opens a modal sheet with one entry per add path — Add book, Add magazine
/// issue and New magazine title push the real forms (S16); Add other item
/// pushes its named placeholder until S17 builds that form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/library/presentation/widgets/add_sheet.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/placeholder_page.dart';

import '../periodicals/application/periodical_fakes.dart';

/// The add form and the sheet need no catalogue data; only the providers the
/// pushed pages read are overridden.
class _EmptyItems implements CatalogueItemRepository {
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async => right(CatalogueItemPage.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

Widget _host() => ProviderScope(
  overrides: [
    catalogueItemRepositoryProvider.overrideWith((ref) async => _EmptyItems()),
    // The pushed add-issue form builds PeriodicalsController (its series
    // picker): repository + the pinned minute tick so the tests settle.
    periodicalRepositoryProvider.overrideWith((ref) async => FakePeriodicals()),
    nowTickProvider.overrideWith((ref) => 0),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showAddSheet(context),
            child: const Text('add'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the sheet lists all four add paths', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('Add book'), findsOneWidget);
    expect(find.text('Add magazine issue'), findsOneWidget);
    expect(find.text('Add other item'), findsOneWidget);
    expect(find.text('New magazine title'), findsOneWidget);
  });

  testWidgets('"Add book" pushes the real add form', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add book'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsOneWidget);
    // The sheet popped itself before pushing.
    expect(find.text('Add magazine issue'), findsNothing);
  });

  /// The magazine entries push the real S16 forms.
  for (final (label, type) in [
    ('Add magazine issue', AddIssuePage),
    ('New magazine title', PeriodicalFormPage),
  ]) {
    testWidgets('"$label" pushes its form (S16)', (tester) async {
      await tester.pumpWidget(_host());
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.byType(type), findsOneWidget);
    });
  }

  testWidgets('"Add other item" pushes its placeholder page (until S17)', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add other item'));
    await tester.pumpAndSettle();

    final page = tester.widget<PlaceholderPage>(find.byType(PlaceholderPage));
    expect(page.pageName, 'Add other item');
  });
}
