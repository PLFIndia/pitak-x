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

/// Minimal wishlist repo so the controller can build; records inserts so
/// tests can inspect what the form actually saved.
class _NoopWishlistRepo implements WishlistRepository {
  final List<WishlistBook> inserted = [];

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook b) async {
    inserted.add(b);
    return right(b);
  }

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

Widget _app(LookupResult result, _NoopWishlistRepo repo) => ProviderScope(
  overrides: [
    isbnLookupServiceProvider.overrideWithValue(_FakeLookup(result)),
    wishlistRepositoryProvider.overrideWith((ref) async => repo),
  ],
  child: const MaterialApp(home: AddWishlistPage()),
);

/// Scrolls the lazy form ListView until [finder] is visible, then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The lookup result SnackBar overlays the bottom of the form (where Add
/// lives) for ~4s; let it expire before tapping anything down there.
Future<void> _letSnackBarExpire(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the add form has a Scan + Lookup control for the ISBN', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LookupNotFound(), _NoopWishlistRepo()));
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
    await tester.pumpWidget(_app(const LookupFound(meta), _NoopWishlistRepo()));
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
    await tester.pumpWidget(_app(const LookupFound(meta), _NoopWishlistRepo()));
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

  // N02 regression: the lookup's cover used to be discarded, and the
  // "needs metadata" flag could never be cleared.
  testWidgets(
    'N02: an allow-listed lookup cover is saved and the metadata flag '
    'clears',
    (tester) async {
      const meta = BookMetadata(
        isbn: '9780140449136',
        title: 'Covered',
        coverUrl: 'https://covers.openlibrary.org/b/id/1.jpg',
      );
      final repo = _NoopWishlistRepo();
      await tester.pumpWidget(_app(const LookupFound(meta), repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ISBN'),
        '9780140449136',
      );
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await _letSnackBarExpire(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Title *'),
        'Covered',
      );
      await _scrollAndTap(tester, find.text('Add'));

      expect(repo.inserted, hasLength(1));
      expect(
        repo.inserted.single.coverUrl,
        'https://covers.openlibrary.org/b/id/1.jpg',
      );
      expect(repo.inserted.single.needsMetadata, isFalse);
    },
  );

  testWidgets('N02: a NON-allow-listed lookup cover is dropped', (
    tester,
  ) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      title: 'Beacon',
      coverUrl: 'https://attacker.example/track.gif',
    );
    final repo = _NoopWishlistRepo();
    await tester.pumpWidget(_app(const LookupFound(meta), repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await _letSnackBarExpire(tester);

    await _scrollAndTap(tester, find.text('Add'));

    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.single.coverUrl, isNull);
  });

  testWidgets('N02: the metadata flag is user-toggleable', (tester) async {
    final repo = _NoopWishlistRepo();
    await tester.pumpWidget(_app(const LookupNotFound(), repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title *'), 'Manual');
    // Flip the explicit switch ON before saving (it is below the fold).
    await tester.scrollUntilVisible(
      find.text('Metadata incomplete'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Metadata incomplete'));
    await tester.pump();
    await _scrollAndTap(tester, find.text('Add'));

    expect(repo.inserted.single.needsMetadata, isTrue);
  });
}
