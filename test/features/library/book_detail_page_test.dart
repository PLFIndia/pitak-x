import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/book_detail_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// N03 widget tests: the detail page must show the CURRENT row, not the
/// snapshot it was pushed with, and an Edit started from it must save on top
/// of the current row (so a cover captured while the page was open survives
/// an unrelated text edit).
///
/// The repository is an in-memory fake whose rows a test can mutate behind
/// the page's back, the way `BookCoverController` / the remote-cover
/// materializer do in production (write the row, then invalidate
/// `libraryControllerProvider`).
class _MemBookRepo implements BookRepository {
  _MemBookRepo(List<Book> seed) : books = List.of(seed);

  final List<Book> books;

  /// When set, `getById` returns this failure (safe-error test).
  Failure? failGetByIdWith;

  int getByIdCalls = 0;

  @override
  Future<Either<Failure, Book?>> getById(int id) async {
    getByIdCalls++;
    final f = failGetByIdWith;
    if (f != null) return left(f);
    return right(books.where((b) => b.id == id).firstOrNull);
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    final i = books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    books[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final saved = book.copyWith(id: books.length + 1, bookUid: 'uid');
    books.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(books);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(books);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

const _seed = Book(
  id: 7,
  bookUid: 'uid-7',
  title: 'Dune',
  author: 'Herbert',
  coverUrl: 'covers/old.jpg',
  copyCount: 2,
);

/// Hosts the detail page ABOVE a home route so `Navigator.pop()` is observable
/// and so the page is pushed the way `LibraryPage` pushes it. Exposes the
/// `ProviderContainer` so a test can invalidate providers the way the
/// application layer does after a background write.
Widget _host(_MemBookRepo repo, String coversDir, {Book? initialBook}) =>
    ProviderScope(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => repo),
        coversDirProvider.overrideWith((ref) async => coversDir),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BookDetailPage(
                      bookId: _seed.id,
                      initialBook: initialBook,
                    ),
                  ),
                ),
                child: const Text('open detail'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('open detail'));
  await tester.pumpAndSettle();
  expect(find.text('Book'), findsOneWidget, reason: 'detail app bar');
}

/// Scrolls the lazy edit form until the save button is built + visible, then
/// taps it. Focus is dropped first: a focused text field scrolls itself back
/// into view once the fling settles, which would unbuild the button again.
Future<void> _tapSave(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final saveBtn = find.byType(FilledButton);
  await tester.scrollUntilVisible(
    saveBtn,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(saveBtn);
  await tester.pumpAndSettle();
}

/// Simulates what every mutation path in the application layer does after
/// writing a row: signal the library that something changed.
void _signalLibraryChanged(WidgetTester tester) {
  ProviderScope.containerOf(
    tester.element(find.byType(BookDetailPage)),
  ).invalidate(libraryControllerProvider);
}

/// A 1×1 PNG so `Image.file` really decodes something.
const _onePxPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00,
  0x1F, 0x15, 0xC4, 0x89, //
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, //
  0x0D, 0x0A, 0x2D, 0xB4, //
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82, //
];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('detail_page_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('N03: renders the initial snapshot on the first frame', (
    tester,
  ) async {
    final repo = _MemBookRepo([_seed]);
    await tester.pumpWidget(_host(repo, tmp.path, initialBook: _seed));
    await tester.tap(find.text('open detail'));
    // ONE frame only: the provider has not resolved yet.
    await tester.pump();
    await tester.pump();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'N03: a row rewritten while the page is open is shown without re-entry',
    (tester) async {
      final repo = _MemBookRepo([_seed]);
      await tester.pumpWidget(_host(repo, tmp.path, initialBook: _seed));
      await _openDetail(tester);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'old.jpg is absent');

      // Background write (what replaceCover / the materializer do): the row
      // now points at a real file; then the shared signal fires.
      File('${tmp.path}/new.png').writeAsBytesSync(_onePxPng);
      await repo.update(
        _seed.copyWith(title: 'Dune Messiah', coverUrl: 'covers/new.png'),
      );
      _signalLibraryChanged(tester);
      await tester.pumpAndSettle();

      expect(find.text('Dune Messiah'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
      expect(find.byType(Image), findsOneWidget, reason: 'new cover renders');
    },
  );

  testWidgets(
    'N03: capture cover → Edit → change text → Save keeps the NEW cover',
    (tester) async {
      final repo = _MemBookRepo([_seed]);
      await tester.pumpWidget(_host(repo, tmp.path, initialBook: _seed));
      await _openDetail(tester);

      // The cover pipeline rewrote the row (and the janitor deleted old.jpg).
      await repo.update(_seed.copyWith(coverUrl: 'covers/new.jpg'));
      _signalLibraryChanged(tester);
      await tester.pumpAndSettle();

      // Edit an unrelated field and save.
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit book'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title *'),
        'Dune (annotated)',
      );
      await _tapSave(tester);

      final saved = repo.books.single;
      expect(saved.title, 'Dune (annotated)');
      expect(
        saved.coverUrl,
        'covers/new.jpg',
        reason: 'the stale snapshot must not resurrect the deleted old cover',
      );
      expect(saved.bookUid, 'uid-7');
      // Back on the detail page, which now shows the edited row (no pop to
      // the list: the page renders truth).
      expect(find.text('Dune (annotated)'), findsOneWidget);
      expect(find.text('open detail'), findsNothing);
    },
  );

  testWidgets('N03: a book deleted underneath shows a safe empty state', (
    tester,
  ) async {
    final repo = _MemBookRepo([_seed]);
    await tester.pumpWidget(_host(repo, tmp.path, initialBook: _seed));
    await _openDetail(tester);

    repo.books.clear();
    _signalLibraryChanged(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    // No actions that would write to a missing row.
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Remove from library'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N03: a repository failure shows a safe message, not raw text', (
    tester,
  ) async {
    final repo = _MemBookRepo([_seed])
      ..failGetByIdWith = const StorageFailure('getById: SQLITE_IOERR');
    await tester.pumpWidget(_host(repo, tmp.path));
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load"), findsOneWidget);
    expect(find.textContaining('SQLITE_IOERR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N03: without a snapshot the page loads the row by id', (
    tester,
  ) async {
    final repo = _MemBookRepo([_seed]);
    await tester.pumpWidget(_host(repo, tmp.path));
    await _openDetail(tester);

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Herbert'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'Quantity row');
    expect(repo.getByIdCalls, greaterThanOrEqualTo(1));
  });
}
