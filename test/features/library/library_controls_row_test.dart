import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';

/// Two languages; `query` honours the language facet like the real repo.
class _Repo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  static const all = [
    CatalogueItem(title: 'Godaan', language: 'Hindi'),
    CatalogueItem(title: 'Dune', language: 'English'),
  ];
  int queryCalls = 0;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(all);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);

  /// Narrows by the facet like the real store (exact match, D1-a) so the
  /// chip tests can see the list change; a search returns everything.
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    queryCalls++;
    final lang = query.language;
    final rows = (query.isSearch || lang == null)
        ? all
        : all.where((b) => b.language == lang).toList();
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      BookPage(items: rows.sublist(start, end), hasMore: end < rows.length),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const ['English', 'Hindi']);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem b) async =>
      right(b);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem b) async =>
      right(b);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

void main() {
  late _Repo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _Repo();
    container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilterChip chip(WidgetTester tester, String label) =>
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

  // Regression (review 2026-09-03, Blocker): the chips read the filter from a
  // mutable field on the LibraryController notifier, which never triggered a
  // rebuild — the list narrowed but the chip never looked selected and the
  // "Clear" chip never appeared, so the user could not see or undo a filter.
  testWidgets('tapping a language chip selects it, narrows the list, and '
      'offers Clear', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(chip(tester, 'Hindi').selected, isFalse);
    expect(find.text('Clear'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();

    expect(chip(tester, 'Hindi').selected, isTrue);
    expect(chip(tester, 'English').selected, isFalse);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(container.read(libraryLanguageFilterProvider), 'Hindi');
  });

  testWidgets('Clear removes the filter and restores the full list', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'English'));
    await tester.pumpAndSettle();
    expect(find.text('Godaan'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear'), findsNothing);
    expect(chip(tester, 'English').selected, isFalse);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(container.read(libraryLanguageFilterProvider), isNull);
  });

  testWidgets('tapping the selected chip again clears it', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'Hindi').selected, isFalse);
    expect(find.text('Dune'), findsOneWidget);
  });

  test('LibraryLanguageFilter treats blank as "no filter"', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(libraryLanguageFilterProvider.notifier).set('  ');
    expect(c.read(libraryLanguageFilterProvider), isNull);
    c.read(libraryLanguageFilterProvider.notifier).set(' Hindi ');
    expect(c.read(libraryLanguageFilterProvider), 'Hindi');
    c.read(libraryLanguageFilterProvider.notifier).clear();
    expect(c.read(libraryLanguageFilterProvider), isNull);
  });
}
