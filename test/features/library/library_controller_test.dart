import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// In-memory repo whose write results are scriptable, so the controller's
/// fail-closed behavior (§5) can be asserted.
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this._all);

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();

  final List<Book> _all;

  /// When set, markRemoved/restoreRemoved return this failure.
  Failure? failWritesWith;

  /// Every page read the controller asked for, in order — N10-d: the
  /// controller must hand the FULL intent (text, sort, facet) plus the
  /// window to the repository, which returns the final rows (no Dart
  /// filter/sort left in the controller).
  final List<({LibraryQuery query, int limit, int offset})> pagesSeen = [];

  /// Sorts seen by page(), to prove the watched sort reaches the repo.
  List<BookSort> get sortsSeen => pagesSeen.map((p) => p.query.sort).toList();

  int markRemovedCalls = 0;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_all);

  /// Slices [_all] like a real store would: a plain listing pages `_all`
  /// verbatim; a search returns nothing (tests that need search rows use a
  /// subclass).
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    pagesSeen.add((query: query, limit: limit, offset: offset));
    if (query.isSearch) return right(BookPage.empty);
    return right(slice(_all, limit: limit, offset: offset));
  }

  /// OFFSET/LIMIT over an in-memory list with the repository's `hasMore`
  /// rule (one row beyond the window exists).
  static BookPage slice(List<Book> rows, {required int limit, int offset = 0}) {
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return BookPage(
      items: rows.sublist(start, end),
      hasMore: end < rows.length,
    );
  }

  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async {
    markRemovedCalls++;
    final f = failWritesWith;
    return f != null ? left(f) : right(unit);
  }

  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async {
    final f = failWritesWith;
    return f != null ? left(f) : right(unit);
  }

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async =>
      right(books.length);
}

/// Repo whose page completions are manually gated by a key, so an OLD
/// read's result can be landed AFTER a newer read's (N05 race). Search reads
/// are keyed by their text; listing reads by `'list@<offset>'`.
class _GatedRepo extends _FakeBookRepo {
  _GatedRepo(super.all);
  final Map<String, Completer<BookPage>> gates = {};

  static String keyFor(LibraryQuery query, int offset) =>
      query.isSearch ? query.text : 'list@$offset';

  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) {
    pagesSeen.add((query: query, limit: limit, offset: offset));
    return (gates[keyFor(query, offset)] ??= Completer<BookPage>()).future.then(
      right,
    );
  }
}

/// Repo whose SEARCH pages a fixed list VERBATIM. N10-d: the repository owns
/// the final order and filter, so whatever it returns must reach the UI
/// untouched — a controller that still re-sorted or re-filtered would change
/// this list.
class _FixedSearchRepo extends _FakeBookRepo {
  _FixedSearchRepo(super.all, this.searchResults);
  final List<Book> searchResults;

  @override
  Future<Either<Failure, BookPage>> page(
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
  Future<Either<Failure, BookPage>> page(
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

/// In-memory settings repo so the settings controller (and its sort value)
/// can be driven without shared_preferences.
class _FakeSettingsRepo implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) async {
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
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);
}

void main() {
  const books = [Book(id: 1, title: 'Dune', author: 'Herbert')];

  /// [n] distinct books, ids 1..n, newest first (the fake pages them as-is).
  List<Book> manyBooks(int n) => List.generate(
    n,
    (i) => Book(id: i + 1, title: 'book ${i + 1}', addedDate: n - i),
  );

  ProviderContainer makeContainer(
    _FakeBookRepo repo, {
    _FakeSettingsRepo? settings,
  }) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
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
    final container = makeContainer(_FakeBookRepo([...books]));
    final window = await container.read(libraryControllerProvider.future);
    expect(window.books.single.title, 'Dune');
    expect(window.hasMore, isFalse);
    expect(window.isLoadingMore, isFalse);
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
  });

  test('successful remove refreshes with data', () async {
    final repo = _FakeBookRepo([...books]);
    final container = makeContainer(repo);
    await container.read(libraryControllerProvider.future);

    await container.read(libraryControllerProvider.notifier).remove(1);

    expect(repo.markRemovedCalls, 1);
    expect(container.read(libraryControllerProvider).hasValue, isTrue);
  });

  test(
    'changing the sort setting reactively reloads with the new sort',
    () async {
      final repo = _FakeBookRepo([...books]);
      final container = makeContainer(repo);
      await container.read(libraryControllerProvider.future);
      expect(repo.sortsSeen, [BookSort.recentlyAdded]);

      // Change the sort through the settings controller — the library
      // controller WATCHES it, so it must rebuild without any manual refresh.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setLibrarySort(BookSort.languageAsc);
      // Allow the dependent provider rebuild to run.
      await container.read(libraryControllerProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(repo.sortsSeen, contains(BookSort.languageAsc));
    },
  );

  // N05 regressions (astra-review.md): a cancelled debounce does NOT cancel
  // an already-running query, and search used to ignore the selected sort.
  test('N05: a slow old search cannot overwrite a newer query', () async {
    final repo = _GatedRepo(const []);
    // A listener mirrors the mounted UI: without it the autoDispose provider
    // is torn down mid-test and cancels its own debounce.
    final container = makeContainer(repo)
      ..listen(libraryControllerProvider, (_, _) {});
    final notifier = container.read(libraryControllerProvider.notifier);
    repo.gates['list@0'] = Completer<BookPage>()..complete(BookPage.empty);
    await container.read(libraryControllerProvider.future);

    notifier.onQueryChanged('slow');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    notifier.onQueryChanged('fast');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Complete the NEW query first, then let the OLD one land late.
    repo.gates['fast']!.complete(
      const BookPage(items: [Book(id: 2, title: 'FAST')], hasMore: false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.gates['slow']!.complete(
      const BookPage(items: [Book(id: 1, title: 'SLOW')], hasMore: false),
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
      const Book(id: 1, title: 'zulu', addedDate: 1, language: 'Zulu'),
      const Book(
        id: 2,
        title: 'afrikaans',
        addedDate: 2,
        language: 'Afrikaans',
      ),
    ];
    final repo = _FixedSearchRepo(const [], fromRepo);
    final settings = _FakeSettingsRepo()
      ..settings = AppSettings.defaults.copyWith(
        librarySort: BookSort.languageAsc,
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
    expect(searchRead.query.sort, BookSort.languageAsc);
    expect(searchRead.query.language, 'Zulu');
    expect(searchRead.offset, 0);
    expect(searchRead.limit, libraryPageSize);
    final titles = windowOf(container).books.map((x) => x.title).toList();
    expect(titles, ['zulu', 'afrikaans']);
  });

  // N10-d part 2 (astra-review.md N10 "lists load the whole catalogue"): the
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
      repo.gates['list@0'] = Completer<BookPage>()
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
      repo.gates['list@0'] = Completer<BookPage>()
        ..complete(_FakeBookRepo.slice(manyBooks(150), limit: 60));
      await container.read(libraryControllerProvider.future);

      final more = notifier.loadMore(); // page 2 of the LISTING, pending
      await Future<void>.delayed(Duration.zero);
      notifier.onQueryChanged('zzz'); // a new list supersedes it
      await Future<void>.delayed(const Duration(milliseconds: 150));
      repo.gates['zzz']!.complete(
        const BookPage(items: [Book(id: 999, title: 'hit')], hasMore: false),
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

        await notifier.refresh();
        expect(repo.pagesSeen.last.offset, 0);
        expect(repo.pagesSeen.last.limit, 120);
        expect(windowOf(container).books, hasLength(120));
        expect(windowOf(container).hasMore, isTrue);

        await notifier.remove(3);
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
          .setLibrarySort(BookSort.ageGroupAsc);
      var window = await container.read(libraryControllerProvider.future);
      expect(repo.pagesSeen.last.query.sort, BookSort.ageGroupAsc);
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
}
