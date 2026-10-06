/// S34 widget tests for the quick-add scan routing (`routeScannedIsbn` in
/// `library_page.dart`): a scanned ISBN that is ALREADY catalogued must offer
/// the existing book instead of an add form the UNIQUE isbn index would only
/// refuse at save time; a new — or unreadable — ISBN falls through to the
/// pre-filled add form (the save path and the index still guard duplicates,
/// so falling through on a read error is safe).
///
/// The camera itself is not exercised here: `ScannerPage` is a thin
/// flutter_zxing wrapper, and the routing under test is what happens AFTER a
/// scan result comes back.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/library/presentation/pages/book_detail_page.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';

/// In-memory repo fake: enough for the pages pushed by the routing
/// (BookDetailPage reads through `bookByIdProvider` → this repo).
class _MemRepo implements BookRepository {
  _MemRepo(this.books);

  final List<Book> books;

  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(books.where((b) => b.id == id).firstOrNull);

  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async => right(BookPage(items: books, hasMore: false));

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(
    isbn.trim().isEmpty ? null : books.where((b) => b.isbn == isbn).firstOrNull,
  );

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(books);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
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

const _existing = Book(
  id: 7,
  bookUid: 'uid-7',
  title: 'Dune',
  isbn: '9780441172719',
);

/// A home route with one button that runs the post-scan routing, the way
/// `_quickAddByScan` does once the scanner popped an ISBN.
Widget _host(
  _MemRepo repo,
  String coversDir,
  String isbn,
  Future<Either<Failure, Book?>> Function(String isbn) findByIsbn,
) => ProviderScope(
  overrides: [
    bookRepositoryProvider.overrideWith((ref) async => repo),
    coversDirProvider.overrideWith((ref) async => coversDir),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => routeScannedIsbn(context, isbn, findByIsbn),
            child: const Text('scan'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_routing_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('a catalogued ISBN offers the EXISTING book, not the add form', (
    tester,
  ) async {
    final repo = _MemRepo([_existing]);
    await tester.pumpWidget(
      _host(repo, tmp.path, _existing.isbn!, (isbn) async => right(_existing)),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    expect(
      find.text("'Dune' is already in your library."),
      findsOneWidget,
      reason: 'the dialog names the existing book',
    );
    expect(find.byType(AddBookPage), findsNothing);

    await tester.tap(find.text('View book'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.text('Dune'), findsWidgets, reason: 'detail header rendered');
  });

  testWidgets('Cancel closes the dialog without navigating', (tester) async {
    final repo = _MemRepo([_existing]);
    await tester.pumpWidget(
      _host(repo, tmp.path, _existing.isbn!, (isbn) async => right(_existing)),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsNothing);
    expect(find.byType(BookDetailPage), findsNothing);
  });

  testWidgets('an unknown ISBN opens the add form pre-filled', (tester) async {
    final repo = _MemRepo([]);
    await tester.pumpWidget(
      _host(repo, tmp.path, '9780140449136', (isbn) async => right(null)),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsOneWidget);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'ISBN'),
    );
    expect(field.controller?.text, '9780140449136');
  });

  testWidgets('a FAILED ISBN read falls through to the add form', (
    tester,
  ) async {
    // Navigation-level fail-through, not a security hole: the add form's save
    // path re-checks and the UNIQUE index makes a duplicate row impossible.
    final repo = _MemRepo([_existing]);
    await tester.pumpWidget(
      _host(
        repo,
        tmp.path,
        _existing.isbn!,
        (isbn) async => left(const StorageFailure('synthetic read failure')),
      ),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsOneWidget);
  });
}
