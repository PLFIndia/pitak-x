import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';

/// N03: the edit form must save on top of the row as it is NOW, not the
/// snapshot the form was opened with. Mirrors `add_book_page_test.dart`.
class _MemWishlistRepo implements WishlistRepository {
  final List<WishlistBook> books = [];

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    final saved = book.copyWith(id: books.length + 1);
    books.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async {
    final i = books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    books[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async =>
      right(books.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(books);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

Widget _host(_MemWishlistRepo repo, WishlistBook book) => ProviderScope(
  overrides: [wishlistRepositoryProvider.overrideWith((ref) async => repo)],
  child: MaterialApp(home: AddWishlistPage(book: book)),
);

/// Scrolls the lazy form ListView until the save button is built + visible,
/// then taps it. The title field is dropped from focus first: a focused text
/// field scrolls itself back into view once the fling settles, which would
/// push the (lazily built) button off screen again before the tap lands.
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

void main() {
  testWidgets('N03: edit saves on top of the CURRENT row, not the snapshot', (
    tester,
  ) async {
    final repo = _MemWishlistRepo();
    final stale = (await repo.insert(
      const WishlistBook(
        title: 'Original',
        coverUrl: 'covers/old.jpg',
        addedDate: 1000,
      ),
    )).getOrElse((_) => throw StateError('seed failed'));
    // The row moved on after the snapshot was taken (cover materialised,
    // purchased elsewhere).
    await repo.update(
      stale.copyWith(
        coverUrl: 'covers/new.jpg',
        purchased: true,
        purchasedDate: 2000,
      ),
    );

    await tester.pumpWidget(_host(repo, stale));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Revised',
    );
    await _tapSave(tester);

    final saved = repo.books.single;
    expect(saved.title, 'Revised');
    expect(saved.coverUrl, 'covers/new.jpg', reason: 'fresh cover kept');
    expect(saved.purchased, isTrue, reason: 'fresh purchase state kept');
    expect(saved.purchasedDate, 2000);
    expect(saved.addedDate, 1000, reason: 'immutable on edit');
  });

  testWidgets('N03: editing a row that vanished shows a safe message', (
    tester,
  ) async {
    final repo = _MemWishlistRepo();
    final gone = (await repo.insert(
      const WishlistBook(title: 'Ghost'),
    )).getOrElse((_) => throw StateError('seed failed'));
    repo.books.clear();

    await tester.pumpWidget(_host(repo, gone));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(repo.books, isEmpty, reason: 'no resurrection by insert');
    expect(find.textContaining('no longer exists'), findsOneWidget);
  });
}
