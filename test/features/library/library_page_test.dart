import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';
import '../app_update/fake_app_update_service.dart';

/// In-memory repo: [getAll] returns [_all]; a search page returns only titles
/// that contain the query (case-insensitive), mimicking the FTS5 contract
/// enough for a widget test without a real database.
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this._all);

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String bookUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();

  final List<CatalogueItem> _all;
  Failure? failWith;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      failWith != null ? left(failWith!) : right(_all);

  /// Every page read the page asked for, as (offset, limit) — N10-d part 2.
  final List<(int, int)> pagesSeen = [];

  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    pagesSeen.add((offset, limit));
    if (failWith != null) return left(failWith!);
    final q = query.text.toLowerCase();
    final rows = query.isSearch
        ? _all.where((b) => b.title.toLowerCase().contains(q)).toList()
        : _all;
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      BookPage(items: rows.sublist(start, end), hasMore: end < rows.length),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  // N03: the detail page observes its row by id, so the fake must answer
  // from the same list the rows came from.
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      failWith != null
      ? left(failWith!)
      : right(_all.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    BookSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
      right(books.length);
}

Widget _app(BookRepository repo) {
  return ProviderScope(
    overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
    child: const MaterialApp(home: LibraryPage()),
  );
}

void main() {
  // Distinct ids: rows are opened by id (N03), and three books sharing the
  // `emptyId` sentinel would be indistinguishable to the detail page.
  const books = [
    CatalogueItem(id: 1, title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
    CatalogueItem(id: 2, title: 'Dune', author: 'Herbert'),
    CatalogueItem(id: 3, title: 'Old Tales', removed: true),
  ];

  testWidgets('renders all books newest-first on load', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Old Tales'), findsOneWidget);
    // copyCount > 1 badge and removed badge are visible.
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
  });

  testWidgets('typing a query filters the list (debounced)', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hobbit');
    // Let the 120ms debounce elapse and the async reload settle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('shows no-matches empty state for a query that hits nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('No matches for "zzzz"'), findsOneWidget);
  });

  testWidgets('shows empty-library state when there are no books', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('the app-bar map button sits left of scan and opens the '
      'network screen on its Map tab', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    final mapButton = find.byTooltip('Network map');
    final scanButton = find.byTooltip('Scan to add');
    expect(mapButton, findsOneWidget);
    expect(scanButton, findsOneWidget);
    expect(
      tester.getTopLeft(mapButton).dx,
      lessThan(tester.getTopLeft(scanButton).dx),
    );

    await tester.tap(mapButton);
    await tester.pumpAndSettle();

    // Landed on the Library network screen's Map tab: without tiles consent
    // the gate asks first instead of building the map (§5.9). (The tab view
    // lazily builds only the visible page, so no network providers run.)
    expect(find.text('Library network'), findsOneWidget);
    expect(find.text('Show the network map?'), findsOneWidget);
  });

  testWidgets('tapping a row opens the detail page', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Hobbit'));
    await tester.pumpAndSettle();

    // Detail page app bar + a labeled row unique to detail.
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
  });

  testWidgets('repository failure shows a safe error, not raw text', (
    tester,
  ) async {
    final repo = _FakeBookRepo(books)..failWith = const StorageFailure('boom');
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load your library"), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  // Review finding N10-d part 2: the screen shows one window and
  // fetches the next as the user nears the end — it never asks for the whole
  // catalogue.
  group('N10-d part 2 — windowed list', () {
    final many = List.generate(
      150,
      (i) => CatalogueItem(
        id: i + 1,
        title: 'Book number ${i + 1}',
        addedDate: 150 - i,
      ),
    );

    testWidgets('first paint reads ONE page and shows only its rows', (
      tester,
    ) async {
      final repo = _FakeBookRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      expect(repo.pagesSeen, [(0, libraryPageSize)]);
      expect(find.text('Book number 1'), findsOneWidget);
      // Row 61 belongs to page 2: not fetched, so not in the tree at all
      // (the list is a lazy sliver, so also check the fake was not asked).
      expect(repo.pagesSeen.any((p) => p.$1 > 0), isFalse);
    });

    testWidgets('scrolling towards the end fetches the next page and appends '
        'its rows; the footer spinner shows while it is pending', (
      tester,
    ) async {
      final repo = _FakeBookRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      // Drag through the first page (~4000 px of rows). Each drag frame lets
      // the NotificationListener see extentAfter shrink under the threshold.
      final list = _bookList();
      for (var i = 0; i < 12 && !repo.pagesSeen.contains((60, 60)); i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump();
      }
      expect(
        repo.pagesSeen,
        contains((60, libraryPageSize)),
        reason: 'page 2 requested near the end of page 1',
      );
      await tester.pumpAndSettle();

      // Rows from page 2 are now reachable.
      await tester.scrollUntilVisible(
        find.text('Book number 90'),
        400,
        scrollable: list,
      );
      expect(find.text('Book number 90'), findsOneWidget);
    });

    testWidgets('the footer progress indicator is visible while page 2 is in '
        'flight and gone once it lands', (tester) async {
      final repo = _SlowSecondPageRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      final list = _bookList();
      for (var i = 0; i < 12 && repo.gate == null; i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump();
      }
      expect(repo.gate, isNotNull, reason: 'page 2 requested');
      // Scroll to the very bottom so the footer is on screen.
      await tester.drag(list, const Offset(0, -5000));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('library-load-more')),
        findsOneWidget,
        reason: 'footer spinner while loading',
      );

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-load-more')), findsNothing);
    });
  });

  // S35: the flexible-update banner is wired atop the library page. With the
  // REAL service it renders nothing in tests (non-Android gate); the fake
  // proves the wiring and the auto-started background download.
  testWidgets('S35: an active app update renders the banner above the list', (
    tester,
  ) async {
    final updates = FakeAppUpdateService(
      availability: AppUpdateAvailability.available,
    );
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
          appUpdateServiceProvider.overrideWithValue(updates),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    // NOT pumpAndSettle: the banner's progress spinner animates forever.
    // The fakes complete in microtasks; explicit frames land every change.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.text('Update downloading in the background…'), findsOneWidget);
    // The library itself still renders underneath.
    expect(find.text('The Hobbit'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (dark theme)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
        ],
        // The shipped dark theme (lib/core/theme/app_theme.dart), not a
        // generic ThemeData.dark(): contrast is checked on real colours.
        child: MaterialApp(theme: AppTheme.dark, home: const LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  // A6 text-scaling smoke test: 2x system font scale must not overflow.
  testWidgets('renders at 2x text scale without overflowing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const LibraryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// The vertical book list's scrollable. `find.byType(Scrollable).first` would
/// pick the HORIZONTAL chips row / text field scrollable that precedes it.
Finder _bookList() => find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

/// Fake whose SECOND page read waits on [gate], so the in-flight footer can
/// be observed.
class _SlowSecondPageRepo extends _FakeBookRepo {
  _SlowSecondPageRepo(super.all);
  Completer<void>? gate;

  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    if (offset > 0) {
      gate ??= Completer<void>();
      await gate!.future;
    }
    return super.page(query, limit: limit, offset: offset);
  }
}
