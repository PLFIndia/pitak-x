import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/presentation/pages/wishlist_page.dart';

/// In-memory wishlist repo with autoincrement ids.
class _MemRepo implements WishlistRepository {
  final List<WishlistBook> books = [];
  int _next = 1;

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    final saved = book.copyWith(id: _next++);
    books.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      insert(book);

  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async {
    final i = books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    books[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    books.removeWhere((b) => b.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async =>
      right(books.where((b) => b.id == id).firstOrNull);

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(books);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

Widget _host(_MemRepo repo) => ProviderScope(
  overrides: [wishlistRepositoryProvider.overrideWith((ref) async => repo)],
  child: const MaterialApp(home: WishlistPage()),
);

void main() {
  testWidgets('empty state when there are no entries', (tester) async {
    await tester.pumpWidget(_host(_MemRepo()));
    await tester.pumpAndSettle();
    expect(find.text('Your wishlist is empty'), findsOneWidget);
  });

  testWidgets('lists active entries and a Purchased section', (tester) async {
    final repo = _MemRepo();
    await repo.insert(const WishlistBook(title: 'Wanted Book'));
    await repo.insert(
      const WishlistBook(title: 'Bought Book', purchased: true),
    );

    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Wanted Book'), findsOneWidget);
    expect(find.text('Bought Book'), findsOneWidget);
    expect(find.text('Purchased'), findsWidgets); // section header + badge
  });

  testWidgets('shows a High priority badge', (tester) async {
    final repo = _MemRepo();
    await repo.insert(
      const WishlistBook(title: 'Urgent', priority: WishlistBook.priorityHigh),
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);
  });
}
