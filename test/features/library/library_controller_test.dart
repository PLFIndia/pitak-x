import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
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

  /// Sorts seen by query(), to prove the watched sort reaches the repo.
  final List<BookSort> sortsSeen = [];

  int markRemovedCalls = 0;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_all);

  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async {
    sortsSeen.add(sort);
    return right(_all);
  }

  @override
  Future<Either<Failure, List<Book>>> search(String query) async =>
      right(const []);

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

/// Repo whose search completions are manually gated, so an OLD query's
/// result can be landed AFTER a newer query's (N05 race).
class _GatedSearchRepo extends _FakeBookRepo {
  _GatedSearchRepo(super.all);
  final Map<String, Completer<List<Book>>> gates = {};

  @override
  Future<Either<Failure, List<Book>>> search(String query) =>
      (gates[query] ??= Completer<List<Book>>()).future.then(right);
}

/// Repo whose search always returns a fixed unsorted list (N05 sort check).
class _FixedSearchRepo extends _FakeBookRepo {
  _FixedSearchRepo(super.all, this.searchResults);
  final List<Book> searchResults;

  @override
  Future<Either<Failure, List<Book>>> search(String query) async =>
      right(searchResults);
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

  test('build loads the book list', () async {
    final container = makeContainer(_FakeBookRepo([...books]));
    final list = await container.read(libraryControllerProvider.future);
    expect(list.single.title, 'Dune');
  });

  test('remove failure surfaces AsyncError(Failure) — never a silent '
      '"success" refresh (§5 fail closed)', () async {
    final repo = _FakeBookRepo([...books])
      ..failWritesWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    await container.read(libraryControllerProvider.future);

    await container.read(libraryControllerProvider.notifier).remove(1);

    final state = container.read(libraryControllerProvider);
    expect(state, isA<AsyncError<List<Book>>>());
    expect(state.error, isA<StorageFailure>());
  });

  test('restoreRemoved failure surfaces AsyncError(Failure)', () async {
    final repo = _FakeBookRepo([...books])
      ..failWritesWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    await container.read(libraryControllerProvider.future);

    await container.read(libraryControllerProvider.notifier).restoreRemoved(1);

    final state = container.read(libraryControllerProvider);
    expect(state, isA<AsyncError<List<Book>>>());
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
    final repo = _GatedSearchRepo(const []);
    // A listener mirrors the mounted UI: without it the autoDispose provider
    // is torn down mid-test and cancels its own debounce.
    final container = makeContainer(repo)
      ..listen(libraryControllerProvider, (_, _) {});
    final notifier = container.read(libraryControllerProvider.notifier);
    await container.read(libraryControllerProvider.future);

    notifier.onQueryChanged('slow');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    notifier.onQueryChanged('fast');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Complete the NEW query first, then let the OLD one land late.
    repo.gates['fast']!.complete([const Book(id: 2, title: 'FAST')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.gates['slow']!.complete([const Book(id: 1, title: 'SLOW')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final list = container.read(libraryControllerProvider).value!;
    expect(list.single.title, 'FAST');
  });

  test('N05: search results honor the persisted sort', () async {
    final repo = _FixedSearchRepo(const [], [
      const Book(id: 1, title: 'zulu', addedDate: 1, language: 'Zulu'),
      const Book(
        id: 2,
        title: 'afrikaans',
        addedDate: 2,
        language: 'Afrikaans',
      ),
    ]);
    final settings = _FakeSettingsRepo()
      ..settings = AppSettings.defaults.copyWith(
        librarySort: BookSort.languageAsc,
      );
    final container = makeContainer(repo, settings: settings)
      ..listen(libraryControllerProvider, (_, _) {}); // keep alive
    final notifier = container.read(libraryControllerProvider.notifier);
    await container.read(libraryControllerProvider.future);

    notifier.onQueryChanged('x');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await container.read(libraryControllerProvider.future);

    final titles = container
        .read(libraryControllerProvider)
        .value!
        .map((x) => x.title)
        .toList();
    expect(titles, ['afrikaans', 'zulu']);
  });
}
