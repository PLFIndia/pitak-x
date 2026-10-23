/// S14 tests for the Library add sheet (`widgets/add_sheet.dart`): the FAB
/// opens a modal sheet with one entry per add path — Add book pushes the real
/// form; the other three push their named placeholders until S15–S17 build
/// those pages.
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
import 'package:pitaka/features/periodicals/presentation/pages/placeholder_page.dart';

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

  /// Each placeholder entry pushes a PlaceholderPage titled after its page.
  for (final (label, pageName) in [
    ('Add magazine issue', 'Add magazine issue'),
    ('Add other item', 'Add other item'),
    ('New magazine title', 'New magazine title'),
  ]) {
    testWidgets('"$label" pushes its placeholder page (until S15–S17)', (
      tester,
    ) async {
      await tester.pumpWidget(_host());
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      final page = tester.widget<PlaceholderPage>(find.byType(PlaceholderPage));
      expect(page.pageName, pageName);
    });
  }
}
