import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// In-memory repo with autoincrement ids, enough to drive add + edit.
class _MemRepo implements BookRepository {
  final List<Book> books = [];
  int _next = 1;

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final saved = book.copyWith(id: _next++, bookUid: 'uid-${book.title}');
    books.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    final i = books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    books[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(books.where((b) => b.id == id).firstOrNull);

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(books);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
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
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
}

/// Scrolls the lazy form ListView until the save button is built + visible,
/// then taps it.
Future<void> _tapSave(WidgetTester tester) async {
  final saveBtn = find.byType(FilledButton);
  await tester.scrollUntilVisible(
    saveBtn,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(saveBtn);
  await tester.pumpAndSettle();
}

Widget _host(_MemRepo repo, {Book? book}) {
  return ProviderScope(
    overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
    child: MaterialApp(home: AddBookPage(book: book)),
  );
}

void main() {
  testWidgets('add mode: blank title shows validation, no insert', (
    tester,
  ) async {
    final repo = _MemRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await _tapSave(tester);
    // The error sits on the title field at the top; scroll back up to see it.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Title *'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('A title is required.'), findsOneWidget);
    expect(repo.books, isEmpty);
  });

  testWidgets('add mode: fills title and saves a new book', (tester) async {
    final repo = _MemRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title *'), 'Dune');
    await _tapSave(tester);

    expect(repo.books.length, 1);
    expect(repo.books.single.title, 'Dune');
    expect(repo.books.single.bookUid, isNotNull);
  });

  testWidgets('edit mode: prefills and updates in place, preserving id', (
    tester,
  ) async {
    final repo = _MemRepo();
    final existing = (await repo.insert(
      const Book(title: 'Original'),
    )).getOrElse((_) => throw StateError('seed failed'));

    await tester.pumpWidget(_host(repo, book: existing));
    await tester.pumpAndSettle();

    // Edit-mode title + prefilled value.
    expect(find.text('Edit book'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Revised',
    );
    await _tapSave(tester);

    expect(repo.books.length, 1);
    expect(repo.books.single.id, existing.id);
    expect(repo.books.single.title, 'Revised');
  });
}
