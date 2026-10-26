import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_state.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';

/// Query intent + derived view (viewer plan S3). The debounce, the facet list
/// and the "a late pass cannot overwrite a newer answer" rule are all pinned
/// here with fakes; no HTTP, no widgets.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  PublishedCatalogueItem item(
    int index, {
    String? title,
    String? language,
    PublishedItemKind kind = PublishedItemKind.book,
  }) => PublishedCatalogueItem(
    sourceIndex: index,
    title: title ?? 'Item $index',
    kind: kind,
    language: language,
  );

  final catalogue = PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: [
      item(0, title: 'English book', language: 'English'),
      item(1, title: 'Hindi book', language: 'Hindi'),
      item(
        2,
        title: 'English issue',
        language: 'english ',
        kind: PublishedItemKind.magazineIssue,
      ),
      item(
        3,
        title: 'Future kind',
        language: 'French',
        kind: PublishedItemKind.unknown,
      ),
    ],
    periodicals: const [],
  );

  late _ImmediateCatalogueFetch fetch;
  late ProviderContainer container;
  late _ControllableRunner runner;
  late ProviderSubscription<PublishedCatalogueQueryState> querySub;

  setUp(() {
    fetch = _ImmediateCatalogueFetch(catalogue);
    runner = _ControllableRunner();
    container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue(fetch.call),
        publishedCatalogueQueryRunnerProvider.overrideWithValue(runner.call),
      ],
    );
    addTearDown(container.dispose);
    // An auto-dispose provider forgets its state the moment nothing listens;
    // these tests exercise the LIVE session, so keep the intent mounted (the
    // way the page does) and close it explicitly where disposal is the point.
    querySub = container.listen(
      publishedCatalogueQueryControllerProvider(site),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(querySub.close);
  });

  PublishedCatalogueQueryController queryController() =>
      container.read(publishedCatalogueQueryControllerProvider(site).notifier);

  PublishedCatalogueQueryState queryState() =>
      container.read(publishedCatalogueQueryControllerProvider(site));

  group('query intent', () {
    test('starts with the documented defaults', () {
      final state = queryState();
      expect(state.search, isEmpty);
      expect(state.activeSearch, isEmpty);
      expect(state.kind, PublishedKindFilter.all);
      expect(state.language, isNull);
      expect(state.sort, PublishedSortOrder.publishedOrder);
      expect(state.hasActiveFilter, isFalse);
    });

    test(
      'typing updates the visible text immediately, the term after 120 ms',
      () async {
        // Baseline: mounting the query controller subscribes to the derived
        // facet list, which reads the loaded catalogue. The contract here is
        // that a KEYSTROKE (not the mount) issues no request at all.
        final callsBefore = fetch.calls.length;
        queryController().search('hindi');
        expect(queryState().search, 'hindi');
        expect(
          queryState().activeSearch,
          isEmpty,
          reason: 'debounce not elapsed',
        );

        await Future<void>.delayed(
          publishedSearchDebounce + const Duration(milliseconds: 40),
        );
        expect(queryState().activeSearch, 'hindi');
        // A typed search is a filter, never IO.
        expect(fetch.calls, hasLength(callsBefore));
      },
    );

    test('a burst of keystrokes applies only the final term', () async {
      final transitions = <String>[];
      final sub = container.listen(
        publishedCatalogueQueryControllerProvider(
          site,
        ).select((s) => s.activeSearch),
        (_, next) => transitions.add(next),
      );
      queryController()
        ..search('h')
        ..search('hi')
        ..search('hin')
        ..search('hindi');
      await Future<void>.delayed(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      expect(queryState().activeSearch, 'hindi');
      expect(transitions, ['hindi']);
      sub.close();
    });

    test('filters and sort apply without debounce or IO', () {
      final callsBefore = fetch.calls.length;
      queryController()
        ..setKind(PublishedKindFilter.books)
        ..setLanguage('English')
        ..setSort(PublishedSortOrder.language);
      final state = queryState();
      expect(state.kind, PublishedKindFilter.books);
      expect(state.language, 'English');
      expect(state.sort, PublishedSortOrder.language);
      expect(
        state.activeQuery,
        isA<PublishedCatalogueQuery>()
            .having((q) => q.kind, 'kind', PublishedKindFilter.books)
            .having((q) => q.language, 'language', 'English')
            .having((q) => q.sort, 'sort', PublishedSortOrder.language),
      );
      expect(fetch.calls, hasLength(callsBefore), reason: 'filters are not IO');
    });

    test('setting the same value does not change the state instance', () {
      final controller = queryController()..setKind(PublishedKindFilter.books);
      final before = queryState();
      controller
        ..setKind(PublishedKindFilter.books)
        ..setSort(PublishedSortOrder.publishedOrder);
      expect(identical(queryState(), before), isTrue);
    });

    test('clearFilters resets search and facets but keeps the sort', () async {
      final controller = queryController()
        ..search('hindi')
        ..setKind(PublishedKindFilter.magazines)
        ..setLanguage('Hindi')
        ..setSort(PublishedSortOrder.ageGroup);
      await Future<void>.delayed(
        publishedSearchDebounce + const Duration(milliseconds: 40),
      );
      controller.clearFilters();
      final state = queryState();
      expect(state.search, isEmpty);
      expect(state.activeSearch, isEmpty);
      expect(state.kind, PublishedKindFilter.all);
      expect(state.language, isNull);
      expect(state.sort, PublishedSortOrder.ageGroup);
      expect(state.hasActiveFilter, isFalse);
    });

    test('a catalogue reload keeps the query intent', () async {
      // A manual reload replaces the catalogue, not the controls: the user's
      // search/filter/sort survives (and no detail-page round trip resets it,
      // because the intent lives in its own auto-dispose provider).
      await container.read(publishedCatalogueControllerProvider(site).future);
      queryController()
        ..search('hindi')
        ..setKind(PublishedKindFilter.books)
        ..setSort(PublishedSortOrder.language);
      await Future<void>.delayed(
        publishedSearchDebounce + const Duration(milliseconds: 40),
      );

      await container
          .read(publishedCatalogueControllerProvider(site).notifier)
          .refresh();

      final state = queryState();
      expect(state.search, 'hindi');
      expect(state.activeSearch, 'hindi');
      expect(state.kind, PublishedKindFilter.books);
      expect(state.sort, PublishedSortOrder.language);
      expect(fetch.calls, hasLength(2), reason: 'reload is one more GET');
    });

    test('disposal cancels the debounce timer', () async {
      // A LOCAL container: the shared one keeps the intent mounted for the
      // other tests, so disposal must be exercised in isolation.
      final local = ProviderContainer();
      addTearDown(local.dispose);
      final sub = local.listen(
        publishedCatalogueQueryControllerProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      local
          .read(publishedCatalogueQueryControllerProvider(site).notifier)
          .search('hindi');
      sub.close();
      await Future<void>.delayed(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      // No StateError from a timer writing state after dispose; a fresh mount
      // starts from the default intent.
      final fresh = local.listen(
        publishedCatalogueQueryControllerProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      expect(
        local.read(publishedCatalogueQueryControllerProvider(site)).search,
        isEmpty,
      );
      fresh.close();
    });
  });

  group('language reconciliation', () {
    PublishedCatalogue withLanguages(List<String> languages) =>
        PublishedCatalogue(
          declaredSchemaVersion: 1,
          items: [
            for (var i = 0; i < languages.length; i++)
              item(i, title: 'Item $i', language: languages[i]),
          ],
          periodicals: const [],
        );

    Future<void> reloadWith(List<String> languages) async {
      fetch.catalogue = withLanguages(languages);
      await container
          .read(publishedCatalogueControllerProvider(site).notifier)
          .refresh();
      // Let the facet listener run on the new payload.
      await Future<void>.delayed(Duration.zero);
    }

    test('a case-only change adopts the new spelling', () async {
      await container.read(publishedCatalogueControllerProvider(site).future);
      queryController()
        ..search('book')
        ..setKind(PublishedKindFilter.books)
        ..setSort(PublishedSortOrder.language)
        ..setLanguage('English');
      await Future<void>.delayed(
        publishedSearchDebounce + const Duration(milliseconds: 40),
      );

      await reloadWith(const ['ENGLISH', 'Hindi']);

      final state = queryState();
      expect(state.language, 'ENGLISH');
      // Everything else is preserved: reconciliation is not a reset.
      expect(state.search, 'book');
      expect(state.activeSearch, 'book');
      expect(state.kind, PublishedKindFilter.books);
      expect(state.sort, PublishedSortOrder.language);
      expect(fetch.calls, hasLength(2), reason: 'one reload, one GET');
    });

    test('an unchanged facet list is a no-op', () async {
      await container.read(publishedCatalogueControllerProvider(site).future);
      queryController().setLanguage('English');
      final before = queryState();

      await reloadWith(const ['English', 'French', 'Hindi']);

      expect(
        identical(queryState(), before),
        isTrue,
        reason: 'no state churn when the spelling did not change',
      );
    });

    test('a vanished selection is cleared, not left invisible', () async {
      await container.read(publishedCatalogueControllerProvider(site).future);
      queryController().setLanguage('French');

      await reloadWith(const ['English', 'Hindi']);

      expect(queryState().language, isNull);
      // "All languages" is a real value: the filter no longer hides rows.
      expect(
        PublishedQueryEngine.apply(
          fetch.catalogue,
          queryState().activeQuery,
        ).shownItems,
        2,
      );
    });

    test('"All languages" is never touched by a reload', () async {
      await container.read(publishedCatalogueControllerProvider(site).future);
      expect(queryState().language, isNull);

      await reloadWith(const ['French']);

      expect(queryState().language, isNull);
    });
  });

  group('derived view', () {
    Future<PublishedCatalogueView> view() async {
      final sub = container.listen(
        publishedCatalogueViewProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(publishedCatalogueControllerProvider(site).future);
      await Future<void>.delayed(Duration.zero);
      // The engine pass is pending: complete the newest one with the real
      // engine result and await it.
      runner.completeLatestWith(catalogue, queryState().activeQuery);
      return container.read(publishedCatalogueViewProvider(site).future);
    }

    test('applies the query to the loaded catalogue', () async {
      final loaded = await view();
      expect(loaded.shownItems, 4);
      expect(loaded.totalItems, 4);
    });

    test('the language facet is derived once from the catalogue', () async {
      final sub = container.listen(
        publishedCatalogueLanguagesProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(publishedCatalogueControllerProvider(site).future);
      expect(container.read(publishedCatalogueLanguagesProvider(site)), [
        'English',
        'French',
        'Hindi',
      ]);
      sub.close();
    });

    test('a late engine pass cannot overwrite a newer answer', () async {
      final sub = container.listen(
        publishedCatalogueViewProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(publishedCatalogueControllerProvider(site).future);
      expect(runner.pending, hasLength(1), reason: 'first pass is running');

      // Change the intent while pass #1 is still pending.
      queryController().setKind(PublishedKindFilter.books);
      await Future<void>.delayed(Duration.zero);
      expect(runner.pending, hasLength(2), reason: 'new intent, new pass');

      // The NEW pass answers first…
      final booksOnly = PublishedQueryEngine.apply(
        catalogue,
        const PublishedCatalogueQuery(kind: PublishedKindFilter.books),
      );
      runner.complete(1, booksOnly);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(publishedCatalogueViewProvider(site)).valueOrNull,
        same(booksOnly),
      );

      // …then the STALE pass finishes. It must be ignored.
      runner.complete(
        0,
        PublishedQueryEngine.apply(catalogue, const PublishedCatalogueQuery()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(publishedCatalogueViewProvider(site)).valueOrNull,
        same(booksOnly),
      );
      sub.close();
    });
  });
}

/// A fetcher that answers immediately with [catalogue].
///
/// [catalogue] is mutable so a test can simulate a RELOAD that ships a
/// different payload (the only way the language facet list changes).
final class _ImmediateCatalogueFetch {
  _ImmediateCatalogueFetch(this.catalogue);

  PublishedCatalogue catalogue;
  final List<String> calls = [];

  Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> call(
    String url, {
    Future<void>? abortTrigger,
  }) async {
    calls.add(url);
    return Right(catalogue);
  }
}

/// A runner whose passes are completed by the test, in any order.
final class _ControllableRunner {
  final List<Completer<PublishedCatalogueView>> pending = [];

  Future<PublishedCatalogueView> call(
    PublishedCatalogue catalogue,
    PublishedCatalogueQuery query,
  ) {
    final completer = Completer<PublishedCatalogueView>();
    pending.add(completer);
    return completer.future;
  }

  void complete(int index, PublishedCatalogueView view) =>
      pending[index].complete(view);

  void completeLatestWith(
    PublishedCatalogue catalogue,
    PublishedCatalogueQuery query,
  ) => pending.last.complete(PublishedQueryEngine.apply(catalogue, query));
}
