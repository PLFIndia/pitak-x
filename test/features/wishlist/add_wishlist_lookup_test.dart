import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';

/// Lookup stub: returns scripted metadata for any ISBN.
class _FakeLookup implements IsbnLookupService {
  _FakeLookup(this._result);
  final LookupResult _result;
  @override
  Future<LookupResult> lookupByIsbn(String isbn) async => _result;
  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async =>
      const SearchEmpty();
}

/// Minimal wishlist repo so the controller can build (never used by lookup).
class _NoopWishlistRepo implements WishlistRepository {
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
}

Widget _app(LookupResult result) => ProviderScope(
  overrides: [
    isbnLookupServiceProvider.overrideWithValue(_FakeLookup(result)),
    wishlistRepositoryProvider.overrideWith((ref) async => _NoopWishlistRepo()),
  ],
  child: const MaterialApp(home: AddWishlistPage()),
);

void main() {
  testWidgets('the add form has a Scan + Lookup control for the ISBN', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LookupNotFound()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('a successful lookup fills empty title/author/publisher/year', (
    tester,
  ) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      title: 'The Looked-Up Title',
      author: 'A. Author',
      publisher: 'Some Press',
      publishedYear: 2014,
    );
    await tester.pumpWidget(_app(const LookupFound(meta)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('The Looked-Up Title'), findsOneWidget);
    expect(find.text('A. Author'), findsOneWidget);
    expect(find.text('Some Press'), findsOneWidget);
    expect(find.text('2014'), findsOneWidget);
  });

  testWidgets('lookup never overwrites a value the user already typed', (
    tester,
  ) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      title: 'Lookup Title',
      author: 'Lookup Author',
    );
    await tester.pumpWidget(_app(const LookupFound(meta)));
    await tester.pumpAndSettle();

    // User typed their own title first.
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'My Title',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // The user's title is kept; the empty author is filled.
    expect(find.text('My Title'), findsOneWidget);
    expect(find.text('Lookup Title'), findsNothing);
    expect(find.text('Lookup Author'), findsOneWidget);
  });
}
