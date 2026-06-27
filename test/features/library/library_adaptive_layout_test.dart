import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/library/presentation/widgets/book_grid_card.dart';
import 'package:pitaka/features/library/presentation/widgets/book_row.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Minimal in-memory repo returning a fixed list (mirrors library_page_test).
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this._all);
  final List<Book> _all;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, List<Book>>> search(String query) async => right(_all);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(_all);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
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

Widget _app() => ProviderScope(
  overrides: [
    bookRepositoryProvider.overrideWith(
      (ref) async => _FakeBookRepo(const [
        Book(title: 'The Hobbit', author: 'Tolkien'),
        Book(title: 'Dune', author: 'Herbert'),
      ]),
    ),
  ],
  child: const MaterialApp(home: LibraryPage()),
);

void main() {
  tearDown(() {
    // Reset any forced surface size between tests.
  });

  testWidgets('narrow window renders the single-column list (BookRow)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(BookRow), findsWidgets);
    expect(find.byType(BookGridCard), findsNothing);
  });

  testWidgets('wide window renders the cover grid (BookGridCard)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(BookGridCard), findsWidgets);
    expect(find.byType(BookRow), findsNothing);
  });
}
