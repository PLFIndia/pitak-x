/// N04 regression tests (astra-review.md): derived providers must re-read
/// their REAL inputs — watching the repository object never fires, because the
/// object itself never changes — and time-based reminders must follow an
/// injectable clock so overdue/due-soon state rolls over while a screen stays
/// mounted.
///
/// The mutation signal is the list controller (N03 precedent): every mutation
/// path in the app already invalidates or refreshes `libraryControllerProvider`
/// / `wishlistControllerProvider`.
///
/// Every test keeps the derived provider ALIVE with an active listener — a
/// bare `container.read` would dispose the autoDispose provider after use and
/// mask the staleness (the next read would simply build a fresh instance).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// In-memory book repo over a MUTABLE list, so a test can change the
/// catalogue behind the provider's back and then fire the mutation signal.
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this.books);

  final List<Book> books;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(List.of(books));

  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(List.of(books));

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    final seen = <String>{};
    for (final b in books) {
      final lang = b.language?.trim() ?? '';
      if (lang.isNotEmpty) seen.add(lang);
    }
    final list = seen.toList()..sort();
    return right(list);
  }

  @override
  Future<Either<Failure, Book?>> getById(int id) async {
    for (final b in books) {
      if (b.id == id) return right(b);
    }
    return right(null);
  }

  // Remaining members: inert defaults (this suite never calls them).
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, List<Book>>> search(String query) async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
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

/// In-memory settings repo so the real `LibraryController` (which watches the
/// persisted sort) can build without shared_preferences.
class _FakeSettingsRepo implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) async =>
      right(unit);
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

/// A session controller that is simply unlocked with fixed data — the derived
/// providers only read `state.valueOrNull`, so the real unlock machinery is
/// not needed here.
class _UnlockedSession extends VaultSessionController {
  _UnlockedSession(this._data);
  final VaultData _data;

  @override
  Future<VaultSessionState> build() async => VaultUnlocked(_data);
}

void main() {
  ProviderContainer makeContainer(
    _FakeBookRepo repo, {
    VaultData? vaultData,
    int Function()? clock,
  }) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
        settingsRepositoryProvider.overrideWith(
          (ref) async => _FakeSettingsRepo(),
        ),
        if (vaultData != null)
          vaultSessionControllerProvider.overrideWith(
            () => _UnlockedSession(vaultData),
          ),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('N04 — derived providers watch their real inputs', () {
    test('libraryLanguages follows a library mutation', () async {
      final repo = _FakeBookRepo([
        const Book(id: 1, title: 'Godaan', language: 'Hindi'),
      ]);
      final container = makeContainer(repo);
      final sub = container.listen(libraryLanguagesProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(libraryControllerProvider.future);
      expect(await container.read(libraryLanguagesProvider.future), ['Hindi']);

      repo.books.add(const Book(id: 2, title: 'Dune', language: 'English'));
      await container.read(libraryControllerProvider.notifier).refresh();

      expect(
        await container.read(libraryLanguagesProvider.future),
        containsAll(<String>['Hindi', 'English']),
      );
    });

    test('bookTitle follows a rename', () async {
      final repo = _FakeBookRepo([const Book(id: 1, title: 'Old title')]);
      final container = makeContainer(repo);
      final sub = container.listen(bookTitleProvider(bookId: 1), (_, __) {});
      addTearDown(sub.close);
      await container.read(libraryControllerProvider.future);
      expect(
        await container.read(bookTitleProvider(bookId: 1).future),
        'Old title',
      );

      repo.books[0] = const Book(id: 1, title: 'New title');
      await container.read(libraryControllerProvider.notifier).refresh();

      expect(
        await container.read(bookTitleProvider(bookId: 1).future),
        'New title',
      );
    });

    test('pendingSnapshot follows a needsMetadata edit', () async {
      final repo = _FakeBookRepo([]);
      final container = makeContainer(repo, vaultData: VaultData.empty);
      final sub = container.listen(pendingSnapshotProvider, (_, __) {});
      addTearDown(sub.close);
      // The session builds asynchronously; await it so the first snapshot
      // read is deterministic (the vault page does the same).
      await container.read(vaultSessionControllerProvider.future);
      await container.read(libraryControllerProvider.future);
      final first = await container.read(pendingSnapshotProvider.future);
      expect(first!.staleMetadataBooks, isEmpty);

      repo.books.add(const Book(id: 1, title: 'Bare', needsMetadata: true));
      await container.read(libraryControllerProvider.notifier).refresh();

      final second = await container.read(pendingSnapshotProvider.future);
      expect(second!.staleMetadataBooks.map((b) => b.title), ['Bare']);
    });
  });

  group('N04 — time-based reminders follow the injected clock', () {
    final t0 = DateTime(2026, 9, 11, 12).millisecondsSinceEpoch;
    const hour = 60 * 60 * 1000;

    Loan loanDueAt(int due) =>
        Loan(id: 1, bookId: 1, borrowerId: 1, lentDate: t0, dueDate: due);

    VaultData vaultWith(Loan loan) => VaultData(
      borrowers: const [Borrower(id: 1, name: 'Asha')],
      loans: [loan],
    );

    test(
      'pendingSnapshot: due-soon becomes overdue when the tick fires',
      () async {
        var now = t0;
        final container = makeContainer(
          _FakeBookRepo([]),
          vaultData: vaultWith(loanDueAt(t0 + hour)),
          clock: () => now,
        );
        final sub = container.listen(pendingSnapshotProvider, (_, __) {});
        addTearDown(sub.close);
        await container.read(vaultSessionControllerProvider.future);

        final before = await container.read(pendingSnapshotProvider.future);
        expect(before!.overdue, isEmpty);
        expect(before.dueSoon, hasLength(1));

        // Time passes beyond the due date; the periodic tick fires (simulated
        // here by invalidating the tick provider — same rebuild path).
        now = t0 + 2 * hour;
        container.invalidate(nowTickProvider);
        // Invalidation schedules the rebuild; pump flushes the scheduler.
        await container.pump();

        final after = await container.read(pendingSnapshotProvider.future);
        expect(after!.overdue, hasLength(1));
        expect(after.dueSoon, isEmpty);
      },
    );

    test('borrowerProfile: overdue rate follows the clock', () async {
      var now = t0;
      final container = makeContainer(
        _FakeBookRepo([]),
        vaultData: vaultWith(loanDueAt(t0 + hour)),
        clock: () => now,
      );
      final sub = container.listen(borrowerProfileProvider(1), (_, __) {});
      addTearDown(sub.close);
      await container.read(vaultSessionControllerProvider.future);

      final before = container.read(borrowerProfileProvider(1));
      expect(before!.stats.overdueRate, 0);

      now = t0 + 2 * hour;
      container.invalidate(nowTickProvider);
      // Invalidation schedules the rebuild; pump flushes the scheduler.
      await container.pump();

      final after = container.read(borrowerProfileProvider(1));
      expect(after!.stats.overdueRate, 1);
    });
  });
}
