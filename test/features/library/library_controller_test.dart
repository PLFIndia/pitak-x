import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// In-memory repo whose write results are scriptable, so the controller's
/// fail-closed behavior (§5) can be asserted.
class _FakeBookRepo implements CatalogueItemRepository {
  _FakeBookRepo(this._all);

  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();

  final List<CatalogueItem> _all;

  /// When set, markRemoved/restoreRemoved return this failure.
  Failure? failWritesWith;

  /// Every page read the controller asked for, in order — N10-d: the
  /// controller must hand the FULL intent (text, sort, facet) plus the
  /// window to the repository, which returns the final rows (no Dart
  /// filter/sort left in the controller).
  final List<({LibraryQuery query, int limit, int offset})> pagesSeen = [];

  /// Sorts seen by page(), to prove the watched sort reaches the repo.
  List<LibrarySort> get sortsSeen =>
      pagesSeen.map((p) => p.query.sort).toList();

  int markRemovedCalls = 0;

  /// When set, markRemoved answers what this completes with, when it does.
  Completer<Either<Failure, Unit>>? heldWrite;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(_all);

  /// Slices [_all] like a real store would: a plain listing pages `_all`
  /// verbatim; a search returns nothing (tests that need search rows use a
  /// subclass).
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    pagesSeen.add((query: query, limit: limit, offset: offset));
    if (query.isSearch) return right(CatalogueItemPage.empty);
    return right(slice(_all, limit: limit, offset: offset));
  }

  /// OFFSET/LIMIT over an in-memory list with the repository's `hasMore`
  /// rule (one row beyond the window exists).
  static CatalogueItemPage slice(
    List<CatalogueItem> rows, {
    required int limit,
    int offset = 0,
  }) {
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return CatalogueItemPage(
      items: rows.sublist(start, end),
      hasMore: end < rows.length,
    );
  }

  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async {
    markRemovedCalls++;
    final held = heldWrite;
    if (held != null) return held.future;
    final f = failWritesWith;
    return f != null ? left(f) : right(unit);
  }

  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async {
    final f = failWritesWith;
    return f != null ? left(f) : right(unit);
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
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

/// Repo whose page completions are manually gated by a key, so an OLD
/// read's result can be landed AFTER a newer read's (N05 race). Search reads
/// are keyed by their text; listing reads by `'list@<offset>'`.
class _GatedRepo extends _FakeBookRepo {
  _GatedRepo(super.all);
  final Map<String, Completer<CatalogueItemPage>> gates = {};

  static String keyFor(LibraryQuery query, int offset) =>
      query.isSearch ? query.text : 'list@$offset';

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) {
    pagesSeen.add((query: query, limit: limit, offset: offset));
    return (gates[keyFor(query, offset)] ??= Completer<CatalogueItemPage>())
        .future
        .then(right);
  }
}

/// Repo whose SEARCH pages a fixed list VERBATIM. N10-d: the repository owns
/// the final order and filter, so whatever it returns must reach the UI
/// untouched — a controller that still re-sorted or re-filtered would change
/// this list.
class _FixedSearchRepo extends _FakeBookRepo {
  _FixedSearchRepo(super.all, this.searchResults);
  final List<CatalogueItem> searchResults;

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    pagesSeen.add((query: query, limit: limit, offset: offset));
    final rows = query.isSearch ? searchResults : _all;
    return right(_FakeBookRepo.slice(rows, limit: limit, offset: offset));
  }
}

/// Repo whose page reads fail after the first [okReads] successes, so
/// `loadMore`'s failure path can be driven while rows are already shown.
class _FailingLaterRepo extends _FakeBookRepo {
  _FailingLaterRepo(super.all, {required this.okReads});
  int okReads;

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    if (okReads-- > 0) {
      return super.page(query, limit: limit, offset: offset);
    }
    pagesSeen.add((query: query, limit: limit, offset: offset));
    return left(const StorageFailure('disk gone'));
  }
}

/// Repo that answers like a store (a plain listing pages every row, a search
/// pages the rows whose title contains the text) and whose reads can be
/// HELD, so a test can look at the list while a read is running (review
/// finding P4-M2): the read with index N of [pagesSeen] waits on `holds[N]`,
/// every other read on [holdAll] while that is set.
class _HeldRepo extends _FakeBookRepo {
  _HeldRepo(super.all);
  final Map<int, Completer<void>> holds = {};
  Completer<void>? holdAll;

  /// When set, every read answers this failure (after its hold).
  Failure? failReadsWith;

  /// When true, every read answers "no rows, and there are more": what a
  /// broken store could say.
  bool moreButNoRows = false;

  /// The rows a real store would hold now; tests add and remove in place.
  List<CatalogueItem> get rows => _all;

  /// Lets every held read go on.
  void release() {
    final all = holdAll;
    holdAll = null;
    all?.complete();
    for (final hold in holds.values) {
      if (!hold.isCompleted) hold.complete();
    }
    holds.clear();
  }

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final index = pagesSeen.length;
    pagesSeen.add((query: query, limit: limit, offset: offset));
    final hold = holds[index] ?? holdAll;
    if (hold != null) await hold.future;
    final failure = failReadsWith;
    if (failure != null) return left(failure);
    if (moreButNoRows) {
      return right(const CatalogueItemPage(items: [], hasMore: true));
    }
    final matching = query.isSearch
        ? _all.where((b) => b.title.contains(query.text)).toList()
        : _all;
    return right(_FakeBookRepo.slice(matching, limit: limit, offset: offset));
  }
}

/// In-memory settings repo so the settings controller (and its sort value)
/// can be driven without shared_preferences.
class _FakeSettingsRepo implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<Either<Failure, Unit>> setLibrarySort(LibrarySort sort) async {
    settings = settings.copyWith(librarySort: sort);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async =>
      right('a' * 32);
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async => right(unit);
  @override
  Future<Either<Failure, String>> regenerateLibraryId() async =>
      right('b' * 32);
  @override
  Future<Either<Failure, Unit>> setMaintainerName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setNetworkMapTilesConsent({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setAutoPublishAvailability({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setLookupIsbnAfterScan({
    required bool enabled,
  }) async => right(unit);
}

void main() {
  const books = [CatalogueItem(id: 1, title: 'Dune', author: 'Herbert')];

  /// [n] distinct books, ids 1..n, newest first (the fake pages them as-is).
  List<CatalogueItem> manyBooks(int n) => List.generate(
    n,
    (i) => CatalogueItem(id: i + 1, title: 'book ${i + 1}', addedDate: n - i),
  );

  ProviderContainer makeContainer(
    _FakeBookRepo repo, {
    _FakeSettingsRepo? settings,
  }) {
    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
        settingsRepositoryProvider.overrideWith(
          (ref) async => settings ?? _FakeSettingsRepo(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Reads the current window (data expected).
  LibraryWindow windowOf(ProviderContainer c) =>
      c.read(libraryControllerProvider).value!;

  test('build loads the first page of the book list', () async {
    final repo = _FakeBookRepo([...books]);
    final container = makeContainer(repo);
    final window = await container.read(libraryControllerProvider.future);
    expect(window.books.single.title, 'Dune');
    expect(window.hasMore, isFalse);
    expect(window.isLoadingMore, isFalse);
    // The store said "no more": one read, although a page has room for more.
    expect(repo.pagesSeen, hasLength(1));
  });

  test('remove failure surfaces AsyncError(Failure) — never a silent '
      '"success" refresh (§5 fail closed)', () async {
    final repo = _FakeBookRepo([...books])
      ..failWritesWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    await container.read(libraryControllerProvider.future);

    await container.read(libraryControllerProvider.notifier).remove(1);

    final state = container.read(libraryControllerProvider);
    expect(state, isA<AsyncError<LibraryWindow>>());
    expect(state.error, isA<StorageFailure>());
    // Nothing was written, so nobody is told to read again (D151).
    expect(container.read(catalogueChangesProvider), 0);
  });

  test('restoreRemoved failure surfaces AsyncError(Failure)', () async {
    final repo = _FakeBookRepo([...books])
      ..failWritesWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    await container.read(libraryControllerProvider.future);

    await container.read(libraryControllerProvider.notifier).restoreRemoved(1);

    final state = container.read(libraryControllerProvider);
    expect(state, isA<AsyncError<LibraryWindow>>());
    expect(state.error, isA<StorageFailure>());
    expect(container.read(catalogueChangesProvider), 0);
  });

  // Rewritten for P4-M2 / P3-M4 (D151, D154): a remove used to reload the
  // list itself and wait for it. Now it tells the app's "catalogue changed"
  // signal, and the list, one listener among others, reads again.
  test('a successful remove says "changed" once and the list reads '
      'again', () async {
    final repo = _FakeBookRepo([...books]);
    final container = makeContainer(repo)
      ..listen(libraryControllerProvider, (_, _) {});
    await container.read(libraryControllerProvider.future);
    final readsBefore = repo.pagesSeen.length;

    await container.read(libraryControllerProvider.notifier).remove(1);

    expect(repo.markRemovedCalls, 1);
    expect(container.read(catalogueChangesProvider), 1);
    await container.read(libraryControllerProvider.future);
    expect(repo.pagesSeen, hasLength(readsBefore + 1));
    expect(container.read(libraryControllerProvider).hasValue, isTrue);
  });

  test(
    'changing the sort setting reactively reloads with the new sort',
    () async {
      final repo = _FakeBookRepo([...books]);
      final container = makeContainer(repo);
      await container.read(libraryControllerProvider.future);
      expect(repo.sortsSeen, [LibrarySort.recentlyAdded]);

      // Change the sort through the settings controller — the library
      // controller WATCHES it, so it must rebuild without any manual refresh.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setLibrarySort(LibrarySort.languageAsc);
      // Allow the dependent provider rebuild to run.
      await container.read(libraryControllerProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(repo.sortsSeen, contains(LibrarySort.languageAsc));
    },
  );

  // Review finding N05 regressions: a cancelled debounce does NOT cancel
  // an already-running query, and search used to ignore the selected sort.
  test('N05: a slow old search cannot overwrite a newer query', () async {
    final repo = _GatedRepo(const []);
    // A listener mirrors the mounted UI: without it the autoDispose provider
    // is torn down mid-test and cancels its own debounce.
    final container = makeContainer(repo)
      ..listen(libraryControllerProvider, (_, _) {});
    final notifier = container.read(libraryControllerProvider.notifier);
    repo.gates['list@0'] = Completer<CatalogueItemPage>()
      ..complete(CatalogueItemPage.empty);
    await container.read(libraryControllerProvider.future);

    notifier.onQueryChanged('slow');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    notifier.onQueryChanged('fast');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Complete the NEW query first, then let the OLD one land late.
    repo.gates['fast']!.complete(
      const CatalogueItemPage(
        items: [CatalogueItem(id: 2, title: 'FAST')],
        hasMore: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.gates['slow']!.complete(
      const CatalogueItemPage(
        items: [CatalogueItem(id: 1, title: 'SLOW')],
        hasMore: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(windowOf(container).books.single.title, 'FAST');
  });

  // N05 pinned "search results honor the persisted sort" by having the
  // controller re-sort in Dart. N10-d moves that duty into the repository's
  // SQL (so a page can be correct), so the controller's contract is now:
  // forward the text, the sort AND the language facet, and show what comes
  // back. The ordering itself is pinned in drift_book_repository_test.dart.
  test('N05/N10-d: search forwards the persisted sort and the language facet '
      'to the repository and shows its rows verbatim', () async {
    // Deliberately NOT in languageAsc order and NOT all Zulu: a controller
    // that still sorted or filtered would change this list.
    final fromRepo = [
      const CatalogueItem(id: 1, title: 'zulu', addedDate: 1, language: 'Zulu'),
      const CatalogueItem(
        id: 2,
        title: 'afrikaans',
        addedDate: 2,
        language: 'Afrikaans',
      ),
    ];
    final repo = _FixedSearchRepo(const [], fromRepo);
    final settings = _FakeSettingsRepo()
      ..settings = AppSettings.defaults.copyWith(
        librarySort: LibrarySort.languageAsc,
      );
    final container = makeContainer(repo, settings: settings)
      ..listen(libraryControllerProvider, (_, _) {}); // keep alive
    container.read(libraryLanguageFilterProvider.notifier).set('Zulu');
    final notifier = container.read(libraryControllerProvider.notifier);
    await container.read(libraryControllerProvider.future);

    notifier.onQueryChanged('x');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await container.read(libraryControllerProvider.future);

    final searchRead = repo.pagesSeen.last;
    expect(searchRead.query.text, 'x');
    expect(searchRead.query.sort, LibrarySort.languageAsc);
    expect(searchRead.query.language, 'Zulu');
    expect(searchRead.offset, 0);
    expect(searchRead.limit, libraryPageSize);
    final titles = windowOf(container).books.map((x) => x.title).toList();
    expect(titles, ['zulu', 'afrikaans']);
  });

  test(
    'U1: the kind chip is a facet of the intent — a tap narrows the '
    'query, tapping the selected kind again clears it (no "All" chip)',
    () async {
      final repo = _FakeBookRepo(manyBooks(3));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {}); // keep alive
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, isNull, reason: 'none = all');

      final chips = container.read(libraryKindFilterProvider.notifier)
        ..toggle(ItemKind.magazineIssue);
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, ItemKind.magazineIssue);
      expect(repo.pagesSeen.last.offset, 0, reason: 'a new intent');

      // Another kind replaces, not combines.
      chips.toggle(ItemKind.other);
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, ItemKind.other);

      // The selected kind again → cleared.
      chips.toggle(ItemKind.other);
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, isNull);
      expect(container.read(libraryKindFilterProvider), isNull);

      // The language facet is untouched by kind taps and travels with it.
      container.read(libraryLanguageFilterProvider.notifier).set('Hindi');
      chips.toggle(ItemKind.book);
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, ItemKind.book);
      expect(repo.pagesSeen.last.query.language, 'Hindi');
      chips.clear();
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.kind, isNull);
      expect(repo.pagesSeen.last.query.language, 'Hindi');
    },
  );

  // Review finding N10-d part 2 ("lists load the whole catalogue"): the
  // controller reads WINDOWS, not the catalogue.
  group('N10-d part 2 — windowed list', () {
    test('build asks for exactly one page (libraryPageSize from offset 0), '
        'never the whole list', () async {
      final repo = _FakeBookRepo(manyBooks(150));
      final container = makeContainer(repo);
      final window = await container.read(libraryControllerProvider.future);

      expect(repo.pagesSeen, hasLength(1));
      expect(repo.pagesSeen.single.limit, libraryPageSize);
      expect(repo.pagesSeen.single.offset, 0);
      expect(window.books, hasLength(libraryPageSize));
      expect(window.hasMore, isTrue);
    });

    test('loadMore appends the next page at offset = rows shown, in order, '
        'and clears hasMore at the end', () async {
      final repo = _FakeBookRepo(manyBooks(150));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      await container.read(libraryControllerProvider.future);

      await notifier.loadMore();
      var window = windowOf(container);
      expect(window.books, hasLength(120));
      expect(window.books.map((b) => b.id).toList(), [
        for (var i = 1; i <= 120; i++) i,
      ]);
      expect(window.hasMore, isTrue);
      expect(repo.pagesSeen.last.offset, 60);
      expect(repo.pagesSeen.last.limit, libraryPageSize);

      await notifier.loadMore();
      window = windowOf(container);
      expect(window.books, hasLength(150));
      expect(window.hasMore, isFalse);

      // Nothing left: no further read is issued.
      final reads = repo.pagesSeen.length;
      await notifier.loadMore();
      expect(repo.pagesSeen, hasLength(reads));
    });

    test('loadMore keeps the list visible while the next page is in flight '
        '(isLoadingMore, not AsyncLoading) and collapses concurrent calls '
        'into one read', () async {
      final repo = _GatedRepo(manyBooks(150));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      repo.gates['list@0'] = Completer<CatalogueItemPage>()
        ..complete(_FakeBookRepo.slice(manyBooks(150), limit: 60));
      await container.read(libraryControllerProvider.future);

      final first = notifier.loadMore();
      final second = notifier.loadMore(); // while the first is pending
      await Future<void>.delayed(Duration.zero);

      final pending = container.read(libraryControllerProvider);
      expect(pending, isA<AsyncData<LibraryWindow>>());
      expect(pending.value!.isLoadingMore, isTrue);
      expect(pending.value!.books, hasLength(60), reason: 'rows stay shown');
      expect(
        repo.pagesSeen.where((p) => p.offset == 60),
        hasLength(1),
        reason: 'one read for two calls',
      );

      repo.gates['list@60']!.complete(
        _FakeBookRepo.slice(manyBooks(150), limit: 60, offset: 60),
      );
      await Future.wait([first, second]);
      final window = windowOf(container);
      expect(window.isLoadingMore, isFalse);
      expect(window.books, hasLength(120));
    });

    test('N05 extended: a late loadMore page from an OLD query is dropped '
        "(never appended to the new query's rows)", () async {
      final repo = _GatedRepo(manyBooks(150));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      repo.gates['list@0'] = Completer<CatalogueItemPage>()
        ..complete(_FakeBookRepo.slice(manyBooks(150), limit: 60));
      await container.read(libraryControllerProvider.future);

      final more = notifier.loadMore(); // page 2 of the LISTING, pending
      await Future<void>.delayed(Duration.zero);
      notifier.onQueryChanged('zzz'); // a new list supersedes it
      await Future<void>.delayed(const Duration(milliseconds: 150));
      repo.gates['zzz']!.complete(
        const CatalogueItemPage(
          items: [CatalogueItem(id: 999, title: 'hit')],
          hasMore: false,
        ),
      );
      await container.read(libraryControllerProvider.future);
      // Now the OLD page-2 lands late.
      repo.gates['list@60']!.complete(
        _FakeBookRepo.slice(manyBooks(150), limit: 60, offset: 60),
      );
      await more;

      final window = windowOf(container);
      expect(window.books.map((b) => b.id).toList(), [999]);
      expect(window.isLoadingMore, isFalse);
      expect(window.hasMore, isFalse);
    });

    // Rewritten for P4-M2 (D153, D154): refresh() and remove() no longer
    // hand back the reload's future (nobody waits for the list any more),
    // so the test waits for the list itself. Up to maxLibraryPageSize rows
    // the reload is still ONE read; beyond it, see the group below.
    test(
      'D2-b: refresh after scrolling two pages reloads the SAME depth in '
      'ONE read so the user keeps their place; a remove does the same',
      () async {
        final repo = _FakeBookRepo(manyBooks(150));
        final container = makeContainer(repo)
          ..listen(libraryControllerProvider, (_, _) {});
        final notifier = container.read(libraryControllerProvider.notifier);
        await container.read(libraryControllerProvider.future);
        await notifier.loadMore();
        expect(windowOf(container).books, hasLength(120));
        var reads = repo.pagesSeen.length;

        notifier.refresh();
        await container.read(libraryControllerProvider.future);
        expect(repo.pagesSeen, hasLength(reads + 1));
        expect(repo.pagesSeen.last.offset, 0);
        expect(repo.pagesSeen.last.limit, 120);
        expect(windowOf(container).books, hasLength(120));
        expect(windowOf(container).hasMore, isTrue);
        reads = repo.pagesSeen.length;

        await notifier.remove(3);
        await container.read(libraryControllerProvider.future);
        expect(repo.pagesSeen, hasLength(reads + 1));
        expect(repo.pagesSeen.last.offset, 0);
        expect(repo.pagesSeen.last.limit, 120);
      },
    );

    test('D2-b: an external invalidate (a write elsewhere) also reloads to '
        'depth — the notifier instance survives the rebuild', () async {
      final repo = _FakeBookRepo(manyBooks(150));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      await container.read(libraryControllerProvider.future);
      await notifier.loadMore();

      container.invalidate(libraryControllerProvider);
      final window = await container.read(libraryControllerProvider.future);

      expect(repo.pagesSeen.last.offset, 0);
      expect(repo.pagesSeen.last.limit, 120);
      expect(window.books, hasLength(120));
    });

    test('a DIFFERENT list (sort change, chip, new text) starts again at one '
        'page — depth is not carried across intents', () async {
      final repo = _FakeBookRepo(manyBooks(150));
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      await container.read(libraryControllerProvider.future);
      await notifier.loadMore();
      expect(windowOf(container).books, hasLength(120));

      // Sort change → rebuild with a different LibraryQuery.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setLibrarySort(LibrarySort.ageGroupAsc);
      var window = await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.sort, LibrarySort.ageGroupAsc);
      expect(repo.pagesSeen.last.limit, libraryPageSize);
      expect(window.books, hasLength(libraryPageSize));

      await notifier.loadMore();
      expect(windowOf(container).books, hasLength(120));

      // Chip → same.
      container.read(libraryLanguageFilterProvider.notifier).set('Hindi');
      window = await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.language, 'Hindi');
      expect(repo.pagesSeen.last.limit, libraryPageSize);
      expect(window.books, hasLength(libraryPageSize));

      // New text → same (debounced).
      await notifier.loadMore();
      notifier.onQueryChanged('q');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.text, 'q');
      expect(repo.pagesSeen.last.limit, libraryPageSize);
    });

    test('a failed loadMore keeps the rows already shown and clears '
        'isLoadingMore so the user can scroll to retry; it is not promoted '
        'to AsyncError', () async {
      final repo = _FailingLaterRepo(manyBooks(150), okReads: 1);
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, _) {});
      final notifier = container.read(libraryControllerProvider.notifier);
      await container.read(libraryControllerProvider.future);

      await notifier.loadMore();

      final state = container.read(libraryControllerProvider);
      expect(state, isA<AsyncData<LibraryWindow>>());
      expect(state.value!.books, hasLength(60));
      expect(state.value!.isLoadingMore, isFalse);
      expect(state.value!.hasMore, isTrue, reason: 'retry stays possible');

      // Retry succeeds.
      repo.okReads = 1;
      await notifier.loadMore();
      expect(windowOf(container).books, hasLength(120));
    });

    test(
      'a failed FIRST page is AsyncError (there is nothing to keep)',
      () async {
        final repo = _FailingLaterRepo(manyBooks(150), okReads: 0);
        final container = makeContainer(repo);
        await expectLater(
          container.read(libraryControllerProvider.future),
          throwsA(isA<StorageFailure>()),
        );
        expect(
          container.read(libraryControllerProvider),
          isA<AsyncError<LibraryWindow>>(),
        );
      },
    );
  });

  // Review findings P4-M2 and P3-M4 (ADR 0031; decisions D151 to D154). The
  // list is one listener of the app's "catalogue changed" signal. While it
  // is read again its rows stay in the state; a deep list is read again in
  // pieces; a load that a newer one overtakes stops.
  group('P4-M2 — the rows stay while the list is read again', () {
    /// A library of [n] books over a store whose reads can be held, loaded
    /// and scrolled to [depth] rows, with a listener, as the screen is one.
    /// The store's record of reads and the recorded states start empty.
    Future<(_HeldRepo, ProviderContainer, List<AsyncValue<LibraryWindow>>)>
    openAt(int depth, {int n = 800}) async {
      final repo = _HeldRepo(manyBooks(n));
      final states = <AsyncValue<LibraryWindow>>[];
      final container = makeContainer(repo)
        ..listen(libraryControllerProvider, (_, next) => states.add(next));
      await container.read(libraryControllerProvider.future);
      final notifier = container.read(libraryControllerProvider.notifier);
      while (windowOf(container).books.length < depth) {
        await notifier.loadMore();
      }
      expect(windowOf(container).books, hasLength(depth));
      repo.pagesSeen.clear();
      states.clear();
      return (repo, container, states);
    }

    List<(int, int)> readsOf(_HeldRepo repo) => [
      for (final p in repo.pagesSeen) (p.offset, p.limit),
    ];

    test('a change is said: the list is read again to where the user was, '
        'in pieces of at most maxLibraryPageSize, and the old rows stay '
        'meanwhile (D152, D153)', () async {
      final (repo, container, states) = await openAt(660);
      final serial = windowOf(container).listSerial;
      // What a write elsewhere did: one row gone, a new one in front.
      repo.rows
        ..removeWhere((b) => b.id == 7)
        ..insert(0, const CatalogueItem(id: 9000, title: 'new'));

      repo.holdAll = Completer<void>();
      container.read(catalogueChangesProvider.notifier).changed();
      final during = container.read(libraryControllerProvider);
      expect(during.isLoading, isTrue);
      expect(during.hasValue, isTrue);
      expect(during.value!.books, hasLength(660));
      expect(during.value!.books.first.id, 1, reason: 'the OLD rows');

      repo.release();
      final window = await container.read(libraryControllerProvider.future);
      expect(readsOf(repo), [(0, maxLibraryPageSize), (500, 160)]);
      expect(window.books, hasLength(660));
      expect(window.books.first.id, 9000);
      expect(window.books.any((b) => b.id == 7), isFalse);
      expect(window.listSerial, serial, reason: 'the same list');
      expect(window.hasMore, isTrue);
      expect(states, isNotEmpty);
      expect(states.every((s) => s.hasValue), isTrue);
    });

    test('a reload that a newer change overtakes reads no further piece, '
        'and its end changes nothing (D153)', () async {
      final (repo, container, _) = await openAt(660);
      // Reload A: its first piece is held.
      final holdA = repo.holds[0] = Completer<void>();
      container.read(catalogueChangesProvider.notifier).changed();
      container.read(libraryControllerProvider); // the list starts reading
      await Future<void>.delayed(Duration.zero);
      expect(readsOf(repo), [(0, 500)], reason: 'A asked for its first piece');

      // A second change while A waits: reload B runs to its end.
      repo.rows.insert(0, const CatalogueItem(id: 9000, title: 'new'));
      container.read(catalogueChangesProvider.notifier).changed();
      final afterB = await container.read(libraryControllerProvider.future);
      expect(afterB.books.first.id, 9000);
      expect(afterB.books, hasLength(660));
      expect(readsOf(repo), [(0, 500), (0, 500), (500, 160)]);

      // Now A's first piece arrives, late.
      holdA.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final end = container.read(libraryControllerProvider);
      expect(repo.pagesSeen, hasLength(3), reason: 'A read no further piece');
      expect(end.hasError, isFalse);
      expect(end.isLoading, isFalse);
      expect(end.value!.books.first.id, 9000);
      expect(end.value!.books, hasLength(660));
    });

    test('two changes said one after the other, before the first reload '
        'has asked the store: ONE read of the head, not two', () async {
      final (repo, container, _) = await openAt(120);
      container.read(catalogueChangesProvider.notifier).changed();
      container.read(libraryControllerProvider); // reload A starts
      container.read(catalogueChangesProvider.notifier).changed();
      await container.read(libraryControllerProvider.future); // reload B
      await Future<void>.delayed(Duration.zero);

      expect(readsOf(repo), [(0, 120)]);
    });

    test('a load of ANOTHER list that ends after a newer load does not '
        'rewrite what the screen shows: the place is kept at the next '
        'change', () async {
      final (repo, container, _) = await openAt(120);
      final notifier = container.read(libraryControllerProvider.notifier);
      final serial = windowOf(container).listSerial;

      // Load A: a search, held.
      final holdA = repo.holds[0] = Completer<void>();
      notifier.onQueryChanged('book 7');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      container.read(libraryControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(repo.pagesSeen.single.query.text, 'book 7');

      // Load B: the text cleared again. The same list as on the screen.
      notifier.onQueryChanged('');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      var window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, serial);
      expect(window.books, hasLength(120));

      // A ends late; then a change is said.
      holdA.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      container.read(catalogueChangesProvider.notifier).changed();
      window = await container.read(libraryControllerProvider.future);

      expect(window.query.text, '');
      expect(window.listSerial, serial, reason: 'still the same list');
      expect(window.books, hasLength(120), reason: 'and to its depth');
    });

    test('a reload that fails shows the error and keeps the old rows behind '
        'it; refresh() reads again, and while it reads the state says both '
        '"loading" and "error"', () async {
      final (repo, container, _) = await openAt(120);
      repo.failReadsWith = const StorageFailure('disk gone');
      container.read(catalogueChangesProvider.notifier).changed();
      await expectLater(
        container.read(libraryControllerProvider.future),
        throwsA(isA<StorageFailure>()),
      );
      final failed = container.read(libraryControllerProvider);
      expect(failed.hasError, isTrue);
      expect(failed.isLoading, isFalse);
      expect(failed.valueOrNull?.books, hasLength(120));

      repo
        ..failReadsWith = null
        ..holdAll = Completer<void>()
        ..pagesSeen.clear();
      container.read(libraryControllerProvider.notifier).refresh();
      final retrying = container.read(libraryControllerProvider);
      expect(retrying.isLoading, isTrue);
      expect(
        retrying.hasError,
        isTrue,
        reason: 'the error screen stays until the answer is there',
      );

      repo.release();
      final window = await container.read(libraryControllerProvider.future);
      expect(container.read(libraryControllerProvider).hasError, isFalse);
      expect(window.books, hasLength(120));
      expect(readsOf(repo), [(0, 120)], reason: 'to the depth it had');
    });

    test('after a deep reload the next page goes on from the right row; a '
        'page that arrives after a change is dropped, and no row stands '
        'twice', () async {
      final (repo, container, _) = await openAt(660);
      container.read(catalogueChangesProvider.notifier).changed();
      await container.read(libraryControllerProvider.future);
      repo.pagesSeen.clear();

      // The next page is asked for and held; a change overtakes it.
      final hold = repo.holds[0] = Completer<void>();
      final more = container
          .read(libraryControllerProvider.notifier)
          .loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(readsOf(repo), [(660, libraryPageSize)]);
      container.read(catalogueChangesProvider.notifier).changed();
      await container.read(libraryControllerProvider.future);
      hold.complete();
      await more;

      var window = windowOf(container);
      final ids = window.books.map((b) => b.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(window.books, hasLength(660));
      expect(window.isLoadingMore, isFalse);

      // The page that was overtaken does not stand in the way of the next:
      // scrolling on reads again.
      await container.read(libraryControllerProvider.notifier).loadMore();
      window = windowOf(container);
      expect(readsOf(repo).last, (660, libraryPageSize));
      expect(window.books, hasLength(720));
    });

    test('a write that fails while the next page is being read: the error '
        'stays, the late page is not painted over it (§5)', () async {
      final (repo, container, _) = await openAt(120);
      final hold = repo.holds[0] = Completer<void>();
      final more = container
          .read(libraryControllerProvider.notifier)
          .loadMore();
      await Future<void>.delayed(Duration.zero);

      repo.failWritesWith = const StorageFailure('disk full');
      await container.read(libraryControllerProvider.notifier).remove(3);
      expect(container.read(libraryControllerProvider).hasError, isTrue);

      hold.complete();
      await more;
      final state = container.read(libraryControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StorageFailure>());
    });

    test('scrolling and typing say nothing to the signal; a remove and a '
        'restore say it once each (P3-M4, D151)', () async {
      final (repo, container, _) = await openAt(60);
      var heard = 0;
      container.listen(catalogueChangesProvider, (_, _) => heard++);
      final notifier = container.read(libraryControllerProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();
      await notifier.loadMore();
      notifier.onQueryChanged('book 1');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen, hasLength(4), reason: 'three pages, one search');
      expect(heard, 0);

      // The notifier is read anew for each write, as the item's page does:
      // that read brings the list up to date first (see `_write`).
      await container.read(libraryControllerProvider.notifier).remove(3);
      expect(heard, 1);
      await container
          .read(libraryControllerProvider.notifier)
          .restoreRemoved(3);
      expect(heard, 2);
    });

    test('remove and restoreRemoved do not wait for the list: they are done '
        'when the write is (D154)', () async {
      final (repo, container, _) = await openAt(120);
      repo.holdAll = Completer<void>(); // the list's next read does not end

      await container
          .read(libraryControllerProvider.notifier)
          .remove(3)
          .timeout(const Duration(seconds: 2));
      expect(
        container.read(libraryControllerProvider).isLoading,
        isTrue,
        reason: 'the list is still reading; the remove is done',
      );
      await container
          .read(libraryControllerProvider.notifier)
          .restoreRemoved(3)
          .timeout(const Duration(seconds: 2));
      expect(container.read(catalogueChangesProvider), 2);

      repo.release();
      await container.read(libraryControllerProvider.future);
    });

    test('another list gets the next serial number and starts at one page; '
        'the same list keeps its number and its depth (D152)', () async {
      final (_, container, _) = await openAt(120);
      final notifier = container.read(libraryControllerProvider.notifier);
      final first = windowOf(container);
      expect(first.query.text, '');

      // The same list: a page more, a change said, a retry.
      await notifier.loadMore();
      expect(windowOf(container).listSerial, first.listSerial);
      container.read(catalogueChangesProvider.notifier).changed();
      var window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial);
      expect(window.books, hasLength(180));
      notifier.refresh();
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial);
      expect(window.books, hasLength(180));

      // Another text ('book 1' is in the title of 111 of the 800 books).
      notifier.onQueryChanged('book 1');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial + 1);
      expect(window.query.text, 'book 1');
      expect(window.books, hasLength(libraryPageSize));

      // A kind chip, then a language chip.
      container.read(libraryKindFilterProvider.notifier).toggle(ItemKind.book);
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial + 2);
      expect(window.query.kind, ItemKind.book);
      container.read(libraryLanguageFilterProvider.notifier).set('Hindi');
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial + 3);
      expect(window.query.language, 'Hindi');

      // The sort.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setLibrarySort(LibrarySort.languageAsc);
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial + 4);
      expect(window.query.sort, LibrarySort.languageAsc);

      // The text cleared: another list again, not "the first one back".
      notifier.onQueryChanged('');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      window = await container.read(libraryControllerProvider.future);
      expect(window.listSerial, first.listSerial + 5);
      expect(window.query.text, '');
      expect(window.books, hasLength(libraryPageSize));
    });

    test('while ANOTHER list is being read the old rows stay in the state, '
        'with their own question and number; after the first load nothing '
        'is ever drawn as the spinner (D152)', () async {
      final (repo, container, states) = await openAt(120);
      final notifier = container.read(libraryControllerProvider.notifier);
      final old = windowOf(container);

      repo.holdAll = Completer<void>();
      notifier.onQueryChanged('book 7');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final during = container.read(libraryControllerProvider);
      expect(during.isLoading, isTrue);
      expect(during.value!.books, hasLength(120));
      expect(
        during.value!.query.text,
        '',
        reason: 'the rows on the screen still answer the OLD question',
      );
      expect(during.value!.listSerial, old.listSerial);

      repo.release();
      final window = await container.read(libraryControllerProvider.future);
      expect(window.query.text, 'book 7');
      expect(window.listSerial, old.listSerial + 1);
      // The page draws the state with `skipLoadingOnReload: true`.
      expect(states, isNotEmpty);
      for (final state in states) {
        expect(
          state.when(
            skipLoadingOnReload: true,
            data: (_) => 'rows',
            error: (_, _) => 'error',
            loading: () => 'spinner',
          ),
          'rows',
        );
      }
    });

    test('letters typed quickly make ONE read, for the last text', () async {
      final (repo, container, _) = await openAt(60);
      final notifier = container.read(libraryControllerProvider.notifier)
        ..onQueryChanged('b')
        ..onQueryChanged('bo')
        ..onQueryChanged('book 7');
      expect(notifier.query, 'book 7');

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.single.query.text, 'book 7');
    });

    test('a change said in the pause after a typed letter reads with the '
        'typed text at once, and the end of the pause brings no second '
        'read of the same list', () async {
      final (repo, container, _) = await openAt(60);
      container
          .read(libraryControllerProvider.notifier)
          .onQueryChanged('book 7');
      container.read(catalogueChangesProvider.notifier).changed();
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.single.query.text, 'book 7');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen, hasLength(1));
    });

    test('a letter typed after a change was said, before the list has '
        'started to read again, is read by that one read too', () async {
      final (repo, container, _) = await openAt(60);
      // The search box holds the notifier, as the page does: its call does
      // not bring the list up to date first.
      final notifier = container.read(libraryControllerProvider.notifier);
      container.read(catalogueChangesProvider.notifier).changed();
      notifier.onQueryChanged('book 7');
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.single.query.text, 'book 7');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen, hasLength(1), reason: 'the pause was dropped');
    });

    test('a write that ends while the list is waiting to be read again '
        'still says "changed" (Riverpod refuses ref.read then)', () async {
      final (repo, container, _) = await openAt(60);
      final write = Completer<Either<Failure, Unit>>();
      repo.heldWrite = write;
      final removing = container
          .read(libraryControllerProvider.notifier)
          .remove(3);
      await Future<void>.delayed(Duration.zero);

      // Another write elsewhere says "changed"; nobody reads the list, so
      // it has not been rebuilt when the held write ends in the same turn.
      container.read(catalogueChangesProvider.notifier).changed();
      write.complete(right(unit));
      await removing;

      expect(container.read(catalogueChangesProvider), 2);
      await container.read(libraryControllerProvider.future);
    });

    test('a page that lands after a change was said, but before the list '
        'has started to read again, is dropped as well', () async {
      final (repo, container, states) = await openAt(120);
      final hold = repo.holds[0] = Completer<void>();
      final more = container
          .read(libraryControllerProvider.notifier)
          .loadMore();
      await Future<void>.delayed(Duration.zero);
      states.clear();

      // Both in one turn: the page's answer is handled before Riverpod has
      // rebuilt the list.
      container.read(catalogueChangesProvider.notifier).changed();
      hold.complete();
      await more;
      final window = await container.read(libraryControllerProvider.future);

      expect(window.books, hasLength(120));
      expect(
        states.where((s) => s.valueOrNull?.books.length == 180),
        isEmpty,
        reason: 'the late page was never put on the screen',
      );
    });

    test('a page asked for in the pause after a typed letter belongs to '
        'the list ON THE SCREEN, not to the text in the box', () async {
      final (repo, container, _) = await openAt(60);
      final notifier = container.read(libraryControllerProvider.notifier)
        ..onQueryChanged('book 7');

      await notifier.loadMore();
      expect(repo.pagesSeen.single.query.text, '');
      expect(repo.pagesSeen.single.offset, 60);
      expect(windowOf(container).books, hasLength(120));

      // The pause ends inside the test, so no timer outlives it.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final window = await container.read(libraryControllerProvider.future);
      expect(window.query.text, 'book 7');
    });

    test('a store that says "there are more" and gives no rows does not '
        'keep the list reading for ever', () async {
      final (repo, container, _) = await openAt(120);
      repo.moreButNoRows = true;
      container.read(catalogueChangesProvider.notifier).changed();

      final window = await container
          .read(libraryControllerProvider.future)
          .timeout(const Duration(seconds: 5));
      expect(repo.pagesSeen, hasLength(1));
      expect(window.books, isEmpty);
    });
  });
}
