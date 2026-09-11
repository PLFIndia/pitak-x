/// N11 (astra-review.md): the merge state machine lives in a keep-alive
/// controller ABOVE the page — a merge writes the catalogue, so once started
/// it must finish even if the user navigates away, a second run must be
/// refused, unexpected throws must become typed terminal states, and the
/// library list refresh must not depend on the page still being there.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_controller.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import '../library/replacement_test_guard.dart';

/// In-memory book repo: just enough surface for the merge use case (mirrors
/// merge_library_use_case_test.dart's fake).
class _FakeBooks implements BookRepository {
  _FakeBooks(this._books);

  final List<Book> _books;
  int _nextId = 1000;

  /// Test-only failure injection for [insertAll].
  Failure? insertAllFailure;

  List<Book> get books => _books;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_books);
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final stored = book.copyWith(
      id: book.id == Book.emptyId ? _nextId++ : book.id,
      bookUid: book.bookUid ?? 'minted-$_nextId',
    );
    _books.add(stored);
    return right(stored);
  }

  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async {
    final failure = insertAllFailure;
    if (failure != null) return left(failure);
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async {
    _books.clear();
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }

  // Unused by the merge use case.
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
}

/// In-memory settings: tracks the library id/name the use case adopts.
class _FakeSettings implements SettingsRepository {
  _FakeSettings({this.libraryId = ''});
  String libraryId;
  String libraryName = '';

  @override
  Future<AppSettings> load() async =>
      AppSettings(libraryName: libraryName, libraryId: libraryId);

  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async =>
      right(libraryId);

  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async {
    libraryId = id;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async {
    libraryName = name;
    return right(unit);
  }

  // Unexpected use of any other settings method must fail this fixture.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const matchingId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  String exportJson({
    required String libraryId,
    List<Map<String, Object?>> books = const [],
  }) => jsonEncode({
    'schemaVersion': 3,
    'libraryId': libraryId,
    'libraryName': 'Other',
    'books': books,
    'wishlist': <Object>[],
  });

  MergeLibraryUseCase useCase({
    _FakeBooks? books,
    _FakeSettings? settings,
    FakeReplacementGuard? guard,
  }) => MergeLibraryUseCase(
    bookRepo: books ?? _FakeBooks([]),
    settings: settings ?? _FakeSettings(libraryId: matchingId),
    jsonParser: const PitakaJsonImporter(),
    replacementGuard: guard ?? FakeReplacementGuard(),
  );

  /// A container holding a live listener on the merge controller (like the
  /// page does), with the use case optionally parked on [gate].
  ProviderContainer makeContainer({
    required MergeLibraryUseCase useCase,
    Completer<void>? gate,
  }) {
    final container = ProviderContainer(
      overrides: [
        mergeLibraryUseCaseProvider.overrideWith((ref) async {
          await gate?.future;
          return useCase;
        }),
        // The library controller (invalidated on a successful merge) needs a
        // repo + settings to build.
        bookRepositoryProvider.overrideWith((ref) async => _FakeBooks([])),
        settingsRepositoryProvider.overrideWith((ref) async => _FakeSettings()),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mergeControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  test(
    'a same-ID file merges and invalidates the library controller',
    () async {
      final books = _FakeBooks([]);
      final container = makeContainer(useCase: useCase(books: books));
      var libraryBuilds = 0;
      container.listen(
        libraryControllerProvider,
        (_, __) => libraryBuilds++,
        fireImmediately: true,
      );
      await container.read(libraryControllerProvider.future);
      final baseline = libraryBuilds;

      await container
          .read(mergeControllerProvider.notifier)
          .mergeText(
            exportJson(
              libraryId: matchingId,
              books: [
                {'bookUid': 'u2', 'title': '1984'},
              ],
            ),
          );

      expect(container.read(mergeControllerProvider), isA<MergeDone>());
      expect(books.books.single.title, '1984');
      await container.pump(); // flush the invalidation into a rebuild
      expect(libraryBuilds, greaterThan(baseline));
    },
  );

  test('a different-ID file surfaces the decision; applyJoin merges and '
      'adopts the incoming ID', () async {
    final settings = _FakeSettings(libraryId: matchingId);
    final books = _FakeBooks([]);
    final container = makeContainer(
      useCase: useCase(books: books, settings: settings),
    );

    await container
        .read(mergeControllerProvider.notifier)
        .mergeText(
          exportJson(
            libraryId: 'b' * 32,
            books: [
              {'bookUid': 'u9', 'title': 'Their book'},
            ],
          ),
        );
    expect(container.read(mergeControllerProvider), isA<MergeNeedsDecision>());

    await container.read(mergeControllerProvider.notifier).applyJoin();
    expect(container.read(mergeControllerProvider), isA<MergeDone>());
    expect(books.books.single.title, 'Their book');
    expect(settings.libraryId, 'b' * 32);
  });

  test(
    'a failed applyJoin keeps the decision and carries the failure',
    () async {
      final books = _FakeBooks([])
        ..insertAllFailure = const StorageFailure('disk full');
      final container = makeContainer(useCase: useCase(books: books));

      await container
          .read(mergeControllerProvider.notifier)
          .mergeText(
            exportJson(
              libraryId: 'b' * 32,
              books: [
                {'bookUid': 'u9', 'title': 'Their book'},
              ],
            ),
          );
      expect(
        container.read(mergeControllerProvider),
        isA<MergeNeedsDecision>(),
      );

      await container.read(mergeControllerProvider.notifier).applyJoin();
      final state = container.read(mergeControllerProvider);
      expect(
        state,
        isA<MergeNeedsDecision>(),
        reason: 'a failed apply must not drop the user off the decision',
      );
      expect((state as MergeNeedsDecision).applyFailure, isA<StorageFailure>());
    },
  );

  test('a second mergeText while one is running is refused', () async {
    final gate = Completer<void>();
    final container = makeContainer(useCase: useCase(), gate: gate);

    final first = container
        .read(mergeControllerProvider.notifier)
        .mergeText(exportJson(libraryId: matchingId));
    var secondDone = false;
    final second = container
        .read(mergeControllerProvider.notifier)
        .mergeText(exportJson(libraryId: matchingId))
        .then((_) => secondDone = true);
    await pumpEventQueue();

    expect(
      secondDone,
      isTrue,
      reason: 'a concurrent merge must be refused immediately, not queued',
    );
    gate.complete();
    await first;
    await second;
    expect(container.read(mergeControllerProvider), isA<MergeDone>());
  });

  test(
    'a throwing use-case provider becomes MergeFailed(UnexpectedFailure)',
    () async {
      final container = ProviderContainer(
        overrides: [
          mergeLibraryUseCaseProvider.overrideWith(
            (ref) async => throw StateError('plugin exploded'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(mergeControllerProvider, (_, __) {});
      addTearDown(sub.close);

      await container.read(mergeControllerProvider.notifier).mergeText('{}');

      final state = container.read(mergeControllerProvider);
      expect(state, isA<MergeFailed>());
      expect((state as MergeFailed).failure, isA<UnexpectedFailure>());
    },
  );

  test(
    'an in-flight merge keeps its terminal state when the page goes away',
    () async {
      // The page watches the controller; popping it removes the last listener.
      // The keep-alive link must keep the element alive until the run ends.
      final gate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          mergeLibraryUseCaseProvider.overrideWith((ref) async {
            await gate.future;
            return useCase();
          }),
          bookRepositoryProvider.overrideWith((ref) async => _FakeBooks([])),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _FakeSettings(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(mergeControllerProvider, (_, __) {});
      final future = container
          .read(mergeControllerProvider.notifier)
          .mergeText(exportJson(libraryId: matchingId));
      expect(container.read(mergeControllerProvider), isA<MergeRunning>());

      sub.close(); // the page is popped: last listener gone
      await container.pump(); // flush the scheduled autoDispose
      gate.complete();
      await future;

      // Same-microtask read: disposal after the keep-alive close is scheduled
      // on the next event-loop turn, so the element is still here.
      expect(
        container.read(mergeControllerProvider),
        isA<MergeDone>(),
        reason: 'the terminal state must survive navigation (keep-alive)',
      );
    },
  );
}
