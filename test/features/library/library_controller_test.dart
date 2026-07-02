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
}

/// In-memory settings repo so the settings controller (and its sort value)
/// can be driven without shared_preferences.
class _FakeSettingsRepo implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> setLibrarySort(BookSort sort) async {
    settings = settings.copyWith(librarySort: sort);
  }

  @override
  Future<void> setThemeMode(AppThemeMode mode) async {}
  @override
  Future<void> setLibraryName(String name) async {}
  @override
  Future<String> getOrCreateLibraryId() async => 'a' * 32;
  @override
  Future<void> setLibraryId(String id) async {}
  @override
  Future<String> regenerateLibraryId() async => 'b' * 32;
  @override
  Future<void> setMaintainerName(String name) async {}
  @override
  Future<void> setLoadRemoteCovers({required bool enabled}) async {}
  @override
  Future<void> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {}
  @override
  Future<void> setLibraryLogo(String reference) async {}
  @override
  Future<void> setAppLockBiometric({required bool enabled}) async {}
}

void main() {
  const books = [Book(id: 1, title: 'Dune', author: 'Herbert')];

  ProviderContainer makeContainer(_FakeBookRepo repo) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
        settingsRepositoryProvider.overrideWith(
          (ref) async => _FakeSettingsRepo(),
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
}
