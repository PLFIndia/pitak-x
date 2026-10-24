import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Empty series store: the row's cover-fallback map
/// (`periodicalCoversProvider`, S14) reads `listAll`; these tests do not seed
/// series, so it stays empty.
class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

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
    CatalogueItem(
      title: 'Weekly 2026-10',
      language: 'English',
      details: IssueOf(periodicalUid: 'per-1', issueNumber: 12),
    ),
    CatalogueItem(
      title: 'Road atlas',
      language: 'English',
      details: OtherItemOf(),
    ),
  ];
  int queryCalls = 0;

  /// The kind facet of every page read, in order — proves the chip's facet
  /// reached the repository as `LibraryQuery.kind`.
  final List<ItemKind?> pagesSeenKinds = [];

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(all);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(all);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);

  /// Narrows by the facets like the real store (exact match, D1-a; kind by
  /// the row's derived kind) so the chip tests can see the list change; a
  /// search returns everything.
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    queryCalls++;
    pagesSeenKinds.add(query.kind);
    var rows = all;
    final lang = query.language;
    if (!query.isSearch && lang != null) {
      rows = rows.where((b) => b.language == lang).toList();
    }
    final kind = query.kind;
    if (!query.isSearch && kind != null) {
      rows = rows.where((b) => b.kind == kind).toList();
    }
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
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
        periodicalRepositoryProvider.overrideWith(
          (ref) async => _NoPeriodicals(),
        ),
        // S14: the row's cover map watches PeriodicalsController, whose build
        // arms the real 60 s nowTick timer — pinned to a constant here so the
        // widget tests can settle (same override vault page tests use).
        nowTickProvider.overrideWith((ref) => 0),
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

  /// Scrolls the horizontal controls row until [finder] is visible, then
  /// taps it. Needed since S14: the kind chips widened the row beyond the
  /// 800 px test surface, so the language chips start off-screen to the
  /// right. The scrollable is the row's own SingleChildScrollView (NOT the
  /// list's).
  Future<void> tapFinder(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Scrolls to the [label] FilterChip and taps it.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tapFinder(tester, find.widgetWithText(FilterChip, label));
  }

  /// Same scroll-then-tap for the "Clear" InputChip.
  Future<void> tapClear(WidgetTester tester) async {
    await tapFinder(tester, find.text('Clear'));
  }

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

    await tapChip(tester, 'Hindi');

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
    await tapChip(tester, 'English');
    expect(find.text('Godaan'), findsNothing);

    await tapClear(tester);

    expect(find.text('Clear'), findsNothing);
    expect(chip(tester, 'English').selected, isFalse);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(container.read(libraryLanguageFilterProvider), isNull);
  });

  testWidgets('tapping the selected chip again clears it', (tester) async {
    await pumpLibrary(tester);
    await tapChip(tester, 'Hindi');
    await tapChip(tester, 'Hindi');
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

  // S14 (ADR 0013 U1): the fixed kind chips toggle the kind facet and the
  // list narrows through `LibraryQuery.kind` — no list plumbing of its own.
  group('kind chips (U1)', () {
    testWidgets('one chip per ItemKind, none selected initially', (
      tester,
    ) async {
      await pumpLibrary(tester);
      for (final kind in ItemKind.values) {
        expect(chip(tester, kind.label).selected, isFalse);
      }
      // No kind facet: every row of the fixture is listed.
      expect(find.text('Godaan'), findsOneWidget);
      expect(find.text('Weekly 2026-10'), findsOneWidget);
      expect(find.text('Road atlas'), findsOneWidget);
    });

    testWidgets('tapping the Magazines chip selects it and narrows the list '
        'to issues', (tester) async {
      await pumpLibrary(tester);

      await tapChip(tester, 'Magazines');

      expect(chip(tester, 'Magazines').selected, isTrue);
      expect(chip(tester, 'Books').selected, isFalse);
      expect(find.text('Weekly 2026-10'), findsOneWidget);
      expect(find.text('Godaan'), findsNothing);
      expect(find.text('Road atlas'), findsNothing);
      expect(container.read(libraryKindFilterProvider), ItemKind.magazineIssue);
      // The facet reached the repository as `LibraryQuery.kind` (the last
      // read after the tap is the narrowed one).
      expect(repo.pagesSeenKinds.last, ItemKind.magazineIssue);
    });

    testWidgets('tapping the selected kind chip again clears the facet', (
      tester,
    ) async {
      await pumpLibrary(tester);
      await tapChip(tester, 'Others');
      expect(find.text('Road atlas'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);

      await tapChip(tester, 'Others');

      expect(chip(tester, 'Others').selected, isFalse);
      expect(container.read(libraryKindFilterProvider), isNull);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Road atlas'), findsOneWidget);
    });

    testWidgets('the kind facet composes with the language facet', (
      tester,
    ) async {
      await pumpLibrary(tester);
      await tapChip(tester, 'Books');
      await tapChip(tester, 'Hindi');

      // Hindi AND book: only Godaan survives both facets.
      expect(find.text('Godaan'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Road atlas'), findsNothing);
    });
  });
}
