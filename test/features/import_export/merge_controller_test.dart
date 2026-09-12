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
import 'package:pitaka/features/settings/application/settings_controller.dart';
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

  /// Test-only failure injection for [update] (N07: a failed row resolution).
  Failure? updateFailure;

  /// When set, [update] parks until completed (N07: an in-flight resolution).
  Completer<void>? updateGate;

  /// When set, [update] throws (N07: an unexpected repository throw).
  bool updateThrows = false;

  /// How many times [update] was called.
  int updateCalls = 0;

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

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    updateCalls++;
    if (updateThrows) throw StateError('db exploded');
    final gate = updateGate;
    if (gate != null) await gate.future;
    final failure = updateFailure;
    if (failure != null) return left(failure);
    final i = _books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    _books[i] = book;
    return right(book);
  }

  // Unused by the merge use case.
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

/// In-memory settings repo behind the REAL `SettingsController` (N07: the
/// use case adopts the library identity THROUGH the controller, so these
/// tests can assert on the controller's in-memory state, not just on disk).
class _FakeSettings implements SettingsRepository {
  _FakeSettings({this.libraryId = ''});
  String libraryId;
  String libraryName = '';

  /// When set, `setLibraryId` fails with it (a failed identity write).
  Failure? setIdFailure;

  @override
  Future<AppSettings> load() async =>
      AppSettings(libraryName: libraryName, libraryId: libraryId);

  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async =>
      right(libraryId);

  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async {
    final failure = setIdFailure;
    if (failure != null) return left(failure);
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

  /// A container holding a live listener on the merge controller (like the
  /// page does). The merge use case is built over [books]/[guard] and the
  /// container's REAL `SettingsController` (over [settings]) as its
  /// `LibraryNamespace` — exactly the production wiring. The use case can be
  /// parked on [gate], or replaced wholesale via [useCaseOverride].
  ProviderContainer makeContainer({
    _FakeBooks? books,
    _FakeSettings? settings,
    FakeReplacementGuard? guard,
    Completer<void>? gate,
    Future<MergeLibraryUseCase> Function()? useCaseOverride,
  }) {
    final repo = settings ?? _FakeSettings(libraryId: matchingId);
    final container = ProviderContainer(
      overrides: [
        mergeLibraryUseCaseProvider.overrideWith((ref) async {
          await gate?.future;
          if (useCaseOverride != null) return useCaseOverride();
          return MergeLibraryUseCase(
            bookRepo: books ?? _FakeBooks([]),
            namespace: ref.read(settingsControllerProvider.notifier),
            jsonParser: const PitakaJsonImporter(),
            replacementGuard: guard ?? FakeReplacementGuard(),
          );
        }),
        // The library controller (invalidated on a successful merge) needs a
        // repo + settings to build.
        bookRepositoryProvider.overrideWith((ref) async => _FakeBooks([])),
        settingsRepositoryProvider.overrideWith((ref) async => repo),
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
      final container = makeContainer(books: books);
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
    final container = makeContainer(books: books, settings: settings);

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
      final settings = _FakeSettings(libraryId: matchingId);
      final container = makeContainer(books: books, settings: settings);

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
      // N07: nothing landed, so this device's identity must be untouched —
      // on disk AND in the controller's memory. Before, the ID was adopted
      // first and the failed insert left the device re-identified.
      expect(settings.libraryId, matchingId);
      expect(
        container.read(settingsControllerProvider).requireValue.libraryId,
        matchingId,
      );
    },
  );

  // N07 (astra-review.md): the use case used to write the adopted ID/name
  // straight into the settings repository, so `SettingsController`'s
  // in-memory state — what the drawer, the library title and the export
  // envelope watch — kept the OLD name until restart.
  group('N07 — settings state follows a namespace adoption', () {
    test(
      'after applyJoin the settings controller shows the new id + name',
      () async {
        final settings = _FakeSettings(libraryId: matchingId)
          ..libraryName = 'Mine';
        final container = makeContainer(settings: settings);
        await container.read(settingsControllerProvider.future);
        expect(
          container.read(settingsControllerProvider).requireValue.libraryName,
          'Mine',
        );

        await container
            .read(mergeControllerProvider.notifier)
            .mergeText(exportJson(libraryId: 'b' * 32));
        await container.read(mergeControllerProvider.notifier).applyJoin();

        final state = container.read(mergeControllerProvider);
        expect(state, isA<MergeDone>());
        expect(
          (state as MergeDone).result.namespace,
          MergeNamespaceOutcome.adopted,
        );
        final current = container.read(settingsControllerProvider).requireValue;
        expect(current.libraryId, 'b' * 32);
        expect(current.libraryName, 'Other');
        // Disk agrees.
        expect(settings.libraryId, 'b' * 32);
        expect(settings.libraryName, 'Other');
      },
    );

    test('an overwrite finishes in MergeDone as a REPLACEMENT with the real '
        'count', () async {
      final books = _FakeBooks([
        const Book(id: 1, bookUid: 'old', title: 'OldBook', addedDate: 1),
      ]);
      final container = makeContainer(books: books);

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
      await container.read(mergeControllerProvider.notifier).applyOverwrite();

      final state = container.read(mergeControllerProvider);
      expect(state, isA<MergeDone>());
      final result = (state as MergeDone).result;
      expect(result.replaced, isTrue);
      expect(result.added, 1);
      expect(books.books.single.title, 'Their book');
    });

    test('books land but the identity write fails → MergeDone with the '
        'omission, not back to the decision', () async {
      final settings = _FakeSettings(libraryId: matchingId)
        ..setIdFailure = const StorageFailure('prefs write failed');
      final books = _FakeBooks([]);
      final container = makeContainer(books: books, settings: settings);

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
      await container.read(mergeControllerProvider.notifier).applyJoin();

      final state = container.read(mergeControllerProvider);
      expect(
        state,
        isA<MergeDone>(),
        reason:
            'the union landed; re-offering "Replace my library" against '
            'an already-merged catalogue would be wrong',
      );
      expect(
        (state as MergeDone).result.namespace,
        MergeNamespaceOutcome.adoptionFailed,
      );
      expect(books.books.single.title, 'Their book');
      expect(settings.libraryId, matchingId, reason: 'old ID still in force');
      expect(
        container.read(settingsControllerProvider).requireValue.libraryId,
        matchingId,
      );
    });
  });

  test('a second mergeText while one is running is refused', () async {
    final gate = Completer<void>();
    final container = makeContainer(gate: gate);

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
            return MergeLibraryUseCase(
              bookRepo: _FakeBooks([]),
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
            );
          }),
          bookRepositoryProvider.overrideWith((ref) async => _FakeBooks([])),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _FakeSettings(libraryId: matchingId),
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

  // N07 part 2 (astra-review.md): "conflicts/possible duplicates are counts
  // only, with no way to inspect or apply the implemented resolutions". The
  // controller now carries one review item per conflict / possible duplicate
  // inside MergeDone and applies the user's choice through the use case.
  group('N07 — per-row review', () {
    /// A same-ID file whose one row conflicts with the local row (genre).
    String conflictingFile() => exportJson(
      libraryId: matchingId,
      books: [
        {'bookUid': 'u1', 'title': 'Godaan', 'genre': 'Classic'},
      ],
    );

    _FakeBooks localWithGodaan() => _FakeBooks([
      const Book(
        id: 1,
        bookUid: 'u1',
        title: 'Godaan',
        genre: 'Fiction',
        addedDate: 1,
      ),
    ]);

    Future<MergeDone> mergeToDone(
      ProviderContainer container,
      String text,
    ) async {
      await container.read(mergeControllerProvider.notifier).mergeText(text);
      final state = container.read(mergeControllerProvider);
      expect(state, isA<MergeDone>());
      return state as MergeDone;
    }

    test('MergeDone carries one pending review item per conflict, in the '
        "engine's order", () async {
      final container = makeContainer(books: localWithGodaan());

      final done = await mergeToDone(container, conflictingFile());

      expect(done.review, hasLength(1));
      final item = done.review.single;
      expect(item.kind, MergeReviewKind.conflict);
      expect(item.local.genre, 'Fiction');
      expect(item.incoming.genre, 'Classic');
      expect(item.status, isA<ReviewPending>());
      expect(done.openCount, 1);
      expect(done.isResolving, isFalse);
    });

    test('resolve(takeTheirs) writes the row, marks it resolved and refreshes '
        'the library', () async {
      final books = localWithGodaan();
      final container = makeContainer(books: books);
      var libraryBuilds = 0;
      container.listen(
        libraryControllerProvider,
        (_, __) => libraryBuilds++,
        fireImmediately: true,
      );
      await container.read(libraryControllerProvider.future);
      await mergeToDone(container, conflictingFile());
      // The merge itself invalidated the list; let that rebuild LAND (its
      // AsyncData is a listener event too) before taking the baseline.
      await container.pump();
      await container.read(libraryControllerProvider.future);
      final baseline = libraryBuilds;

      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);

      final done = container.read(mergeControllerProvider) as MergeDone;
      final status = done.review.single.status;
      expect(status, isA<ReviewResolved>());
      expect((status as ReviewResolved).resolution, MergeResolution.takeTheirs);
      expect(done.openCount, 0);
      expect(books.books.single.genre, 'Classic');
      expect(books.books.single.id, 1, reason: 'in place');
      await container.pump();
      expect(libraryBuilds, greaterThan(baseline));
    });

    test('resolve(keepMine) resolves without a write and without a '
        'refresh', () async {
      final books = localWithGodaan();
      final container = makeContainer(books: books);
      var libraryBuilds = 0;
      container.listen(
        libraryControllerProvider,
        (_, __) => libraryBuilds++,
        fireImmediately: true,
      );
      await container.read(libraryControllerProvider.future);
      await mergeToDone(container, conflictingFile());
      await container.pump();
      await container.read(libraryControllerProvider.future);
      final baseline = libraryBuilds;

      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.keepMine);

      final done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.review.single.status, isA<ReviewResolved>());
      expect(books.updateCalls, 0);
      expect(books.books.single.genre, 'Fiction');
      await container.pump();
      expect(libraryBuilds, baseline, reason: 'nothing changed on disk');
    });

    test('a failed resolution keeps the item open with the typed failure; '
        'a retry can then succeed', () async {
      final books = localWithGodaan()
        ..updateFailure = const StorageFailure('disk full');
      final container = makeContainer(books: books);
      await mergeToDone(container, conflictingFile());

      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);

      var done = container.read(mergeControllerProvider) as MergeDone;
      var status = done.review.single.status;
      expect(status, isA<ReviewFailed>());
      expect((status as ReviewFailed).failure, isA<StorageFailure>());
      expect(done.openCount, 1, reason: 'still open for a retry');

      books.updateFailure = null;
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);

      done = container.read(mergeControllerProvider) as MergeDone;
      status = done.review.single.status;
      expect(status, isA<ReviewResolved>());
      expect(books.books.single.genre, 'Classic');
    });

    test(
      'a throwing repository becomes ReviewFailed(UnexpectedFailure)',
      () async {
        final books = localWithGodaan()..updateThrows = true;
        final container = makeContainer(books: books);
        await mergeToDone(container, conflictingFile());

        await container
            .read(mergeControllerProvider.notifier)
            .resolve(0, MergeResolution.takeTheirs);

        final done = container.read(mergeControllerProvider) as MergeDone;
        final status = done.review.single.status;
        expect(status, isA<ReviewFailed>());
        expect((status as ReviewFailed).failure, isA<UnexpectedFailure>());
      },
    );

    test('only one resolution runs at a time; a second call on another item '
        'is refused while the first is in flight', () async {
      final books = _FakeBooks([
        const Book(
          id: 1,
          bookUid: 'u1',
          title: 'Godaan',
          genre: 'Fiction',
          addedDate: 1,
        ),
        const Book(
          id: 2,
          bookUid: 'u2',
          title: 'Nirmala',
          genre: 'Fiction',
          addedDate: 1,
        ),
      ]);
      final gate = Completer<void>();
      books.updateGate = gate;
      final container = makeContainer(books: books);
      await mergeToDone(
        container,
        exportJson(
          libraryId: matchingId,
          books: [
            {'bookUid': 'u1', 'title': 'Godaan', 'genre': 'Classic'},
            {'bookUid': 'u2', 'title': 'Nirmala', 'genre': 'Classic'},
          ],
        ),
      );

      final first = container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);
      await pumpEventQueue();
      var done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.isResolving, isTrue);
      expect(done.review[0].status, isA<ReviewApplying>());

      await container
          .read(mergeControllerProvider.notifier)
          .resolve(1, MergeResolution.takeTheirs);
      done = container.read(mergeControllerProvider) as MergeDone;
      expect(
        done.review[1].status,
        isA<ReviewPending>(),
        reason: 'refused, not queued',
      );
      expect(books.updateCalls, 1);

      gate.complete();
      await first;
      done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.review[0].status, isA<ReviewResolved>());
      expect(done.review[1].status, isA<ReviewPending>());
      expect(done.isResolving, isFalse);
    });

    test('a resolved item cannot be resolved again', () async {
      final books = localWithGodaan();
      final container = makeContainer(books: books);
      await mergeToDone(container, conflictingFile());

      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.keepMine);
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);

      expect(books.updateCalls, 0);
      expect(books.books.single.genre, 'Fiction');
    });

    test('resolve outside MergeDone or with a bad index is a no-op', () async {
      final books = localWithGodaan();
      final container = makeContainer(books: books);

      // Idle: nothing to resolve.
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);
      expect(container.read(mergeControllerProvider), isA<MergeIdle>());

      await mergeToDone(container, conflictingFile());
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(5, MergeResolution.takeTheirs);
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(-1, MergeResolution.takeTheirs);
      expect(books.updateCalls, 0);
      final done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.review.single.status, isA<ReviewPending>());
    });

    test('mergeText is refused while a resolution is in flight', () async {
      final books = localWithGodaan();
      final gate = Completer<void>();
      books.updateGate = gate;
      final container = makeContainer(books: books);
      await mergeToDone(container, conflictingFile());

      final resolving = container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);
      await pumpEventQueue();

      await container
          .read(mergeControllerProvider.notifier)
          .mergeText(conflictingFile());
      expect(
        container.read(mergeControllerProvider),
        isA<MergeDone>(),
        reason: 'the new pick was refused; still the same MergeDone',
      );

      gate.complete();
      await resolving;
      final done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.review.single.status, isA<ReviewResolved>());
    });

    test('an in-file collision item offers no take-theirs (local was never '
        'persisted)', () async {
      final container = makeContainer(books: _FakeBooks([]));

      final done = await mergeToDone(
        container,
        exportJson(
          libraryId: matchingId,
          books: [
            {'bookUid': 'uB', 'title': 'Godaan'},
            {'bookUid': 'uB', 'title': 'Godaan (duplicate row)'},
          ],
        ),
      );

      final item = done.review.single;
      expect(item.kind, MergeReviewKind.inFileCollision);
      expect(item.canTakeTheirs, isFalse);

      // Belt and braces: even if a caller ignores `canTakeTheirs`, the use
      // case refuses and the item stays open with a typed failure.
      await container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);
      final after = container.read(mergeControllerProvider) as MergeDone;
      expect(after.review.single.status, isA<ReviewFailed>());
      expect(
        (after.review.single.status as ReviewFailed).failure,
        isA<ValidationFailure>(),
      );
    });

    test('an in-flight resolution survives the page going away (keep-alive) '
        'and its completion lands in the same MergeDone', () async {
      final books = localWithGodaan();
      final gate = Completer<void>();
      books.updateGate = gate;
      // Own container: the test controls the ONLY listener (the "page").
      final container = ProviderContainer(
        overrides: [
          mergeLibraryUseCaseProvider.overrideWith(
            (ref) async => MergeLibraryUseCase(
              bookRepo: books,
              namespace: ref.read(settingsControllerProvider.notifier),
              jsonParser: const PitakaJsonImporter(),
              replacementGuard: FakeReplacementGuard(),
            ),
          ),
          bookRepositoryProvider.overrideWith((ref) async => _FakeBooks([])),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _FakeSettings(libraryId: matchingId),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(mergeControllerProvider, (_, __) {});
      await mergeToDone(container, conflictingFile());

      final resolving = container
          .read(mergeControllerProvider.notifier)
          .resolve(0, MergeResolution.takeTheirs);
      await pumpEventQueue();

      sub.close(); // the page is popped: last listener gone
      await container.pump(); // flush the scheduled autoDispose
      gate.complete();
      await resolving;

      // Same-microtask read (see the N11 test above for why this is valid).
      final done = container.read(mergeControllerProvider) as MergeDone;
      expect(done.review.single.status, isA<ReviewResolved>());
      expect(books.books.single.genre, 'Classic');
    });
  });
}
