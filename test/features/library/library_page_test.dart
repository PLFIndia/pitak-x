import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// In-memory repo: [getAll] returns [_all]; [search] returns only titles that
/// contain the query (case-insensitive), mimicking the FTS5 contract enough for
/// a widget test without a real database.
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this._all);

  final List<Book> _all;
  Failure? failWith;

  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
      failWith != null ? left(failWith!) : right(_all);

  @override
  Future<Either<Failure, List<Book>>> search(String query) async {
    if (failWith != null) return left(failWith!);
    final q = query.trim().toLowerCase();
    return right(_all.where((b) => b.title.toLowerCase().contains(q)).toList());
  }

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
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
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async =>
      right(books.length);
}

Widget _app(BookRepository repo) {
  return ProviderScope(
    overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
    child: const MaterialApp(home: LibraryPage()),
  );
}

void main() {
  const books = [
    Book(title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
    Book(title: 'Dune', author: 'Herbert'),
    Book(title: 'Old Tales', removed: true),
  ];

  testWidgets('renders all books newest-first on load', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Old Tales'), findsOneWidget);
    // copyCount > 1 badge and removed badge are visible.
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
  });

  testWidgets('typing a query filters the list (debounced)', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hobbit');
    // Let the 120ms debounce elapse and the async reload settle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('shows no-matches empty state for a query that hits nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('No matches for "zzzz"'), findsOneWidget);
  });

  testWidgets('shows empty-library state when there are no books', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('tapping a row opens the detail page', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Hobbit'));
    await tester.pumpAndSettle();

    // Detail page app bar + a labeled row unique to detail.
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
  });

  testWidgets('repository failure shows a safe error, not raw text', (
    tester,
  ) async {
    final repo = _FakeBookRepo(books)..failWith = const StorageFailure('boom');
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load your library"), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });
}
