/// What the wishlist form does when the user leaves it (review finding
/// P4-M1): Back must not throw away what was typed without asking.
///
/// The form stands ABOVE a home page here, as in the app; "the form is
/// gone" means the home page shows again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/form_back_harness.dart';

/// Lookup stub: answers every ISBN with the scripted result.
class _FakeLookup implements IsbnLookupService {
  _FakeLookup(this._result);
  final LookupResult _result;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async => _result;

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async =>
      const SearchEmpty();
}

/// An in-memory wishlist with two places where a test can hold a call open
/// (the write of a save, and the list reload that follows it) and a save
/// that can be made to fail.
class _HeldWishlist implements WishlistRepository {
  final List<WishlistBook> books = [];

  /// While set, `insert` waits for it before it stores anything.
  Completer<void>? holdInsert;

  /// While set, every list read (`getAll`) waits for it.
  Completer<void>? holdGetAll;

  /// When set, `insert` answers this failure and stores nothing.
  Failure? insertFailure;

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    await holdInsert?.future;
    final failure = insertFailure;
    if (failure != null) return left(failure);
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
  Future<Either<Failure, List<WishlistBook>>> getAll() async {
    await holdGetAll?.future;
    return right(List.of(books));
  }

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

/// Camera replacement: one button that emits a valid ISBN to ScannerPage.
Widget _fakeScanner(void Function(String) onText) => ElevatedButton(
  onPressed: () => onText('9780140449136'),
  child: const Text('emit-isbn'),
);

void main() {
  late _HeldWishlist repo;

  setUp(() {
    repo = _HeldWishlist();
    SharedPreferences.setMockInitialValues({});
  });

  final title = find.widgetWithText(TextField, 'Title *');
  final page = find.byType(AddWishlistPage);

  /// Opens the form above the home page, on a surface tall enough to build
  /// every field (the form is a list that builds what is near the screen
  /// only).
  Future<void> openForm(
    WidgetTester tester, {
    WishlistBook? book,
    LookupResult lookup = const LookupNotFound(),
    IsbnScannerBuilder? buildScanner,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFormAboveHome(
      tester,
      AddWishlistPage(book: book, buildScanner: buildScanner),
      overrides: [
        wishlistRepositoryProvider.overrideWith((ref) async => repo),
        isbnLookupServiceProvider.overrideWithValue(_FakeLookup(lookup)),
      ],
    );
  }

  void expectGoneWithoutQuestion() {
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsNothing);
    expect(findFormBackHome(), findsOneWidget);
  }

  void expectAsked() {
    expect(findDiscardQuestion(), findsOneWidget);
    expect(page, findsOneWidget);
  }

  /// Taps Save without waiting for the screen to come to rest: while a save
  /// is held open the button shows a spinner that never rests.
  Future<void> tapSaveAndHold(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
  }

  /// The lookup's SnackBar stays for about four seconds; let it go.
  Future<void> letSnackBarExpire(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Has the wishlist loaded and listened to before a save, as it is in the
  /// app, where the Wishlist screen under the form watches it. Without this
  /// the list is built for the FIRST time by the form's reload after a
  /// save, which never happens in the app.
  Future<void> keepWishlistLoaded(WidgetTester tester) async {
    final subscription = ProviderScope.containerOf(
      tester.element(page),
    ).listen(wishlistControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    await tester.pumpAndSettle();
  }

  /// An entry with every field of the form filled in, to edit.
  Future<WishlistBook> seedFullEntry() async => (await repo.insert(
    const WishlistBook(
      title: 'Dune',
      author: 'Frank Herbert',
      isbn: '9780140449136',
      publisher: 'Chilton',
      publishedYear: 1965,
      priceEstimate: 450,
      priority: WishlistBook.priorityHigh,
      notes: 'The first edition if possible',
      addedDate: 1000,
    ),
  )).getOrElse((_) => throw StateError('seed failed'));

  testWidgets('untouched, Back: the form leaves at once', (tester) async {
    await openForm(tester);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('an edit form opened and left as it was: Back leaves', (
    tester,
  ) async {
    await openForm(tester, book: await seedFullEntry());
    expect(find.text('Edit wishlist item'), findsOneWidget);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('a title typed, Back: the question. "Keep editing" keeps the '
      'form and the text; Back again and "Discard" leaves', (tester) async {
    await openForm(tester);
    await tester.enterText(title, 'Dune');
    await pressSystemBack(tester);
    expectAsked();
    expect(
      find.text('What you entered on this page has not been saved.'),
      findsOneWidget,
    );

    await tester.tap(findKeepEditing());
    await tester.pumpAndSettle();
    expect(findDiscardQuestion(), findsNothing);
    expect(find.widgetWithText(TextField, 'Dune'), findsOneWidget);

    await pressSystemBack(tester);
    await tester.tap(findDiscard());
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(repo.books, isEmpty, reason: 'discarded, not saved');
  });

  testWidgets('the arrow of the app bar asks as well', (tester) async {
    await openForm(tester);
    await tester.enterText(title, 'Dune');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expectAsked();
  });

  testWidgets('typed and put back, Back: leaves', (tester) async {
    await openForm(tester);
    await tester.enterText(title, 'Dune');
    await tester.enterText(title, '');
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  // Every text field the form shows. A field that is added to the page has
  // to be added here (the count below fails otherwise), and then its own
  // test says whether the guard knows of it.
  const textFields = [
    'Title *',
    'Author',
    'ISBN',
    'Publisher',
    'Published year',
    'Price estimate',
    'Notes',
  ];

  testWidgets('the form shows exactly the text fields these tests know', (
    tester,
  ) async {
    await openForm(tester);

    expect(find.byType(TextField), findsNWidgets(textFields.length));
    for (final label in textFields) {
      expect(find.widgetWithText(TextField, label), findsOneWidget);
    }
  });

  for (final label in textFields) {
    testWidgets('"$label" changed, Back: the question', (tester) async {
      await openForm(tester);
      // A digit: the field for the year takes nothing else.
      await tester.enterText(find.widgetWithText(TextField, label), '7');
      await pressSystemBack(tester);

      expectAsked();
    });
  }

  group('a value that is not typed text', () {
    testWidgets('another priority picked: the question', (tester) async {
      await openForm(tester);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('"Metadata incomplete" switched on: the question; switched '
        'off again: Back leaves', (tester) async {
      await openForm(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await pressSystemBack(tester);
      expectAsked();

      await tester.tap(findKeepEditing());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await pressSystemBack(tester);
      expectGoneWithoutQuestion();
    });

    testWidgets('a barcode scanned inside the form: the question', (
      tester,
    ) async {
      await openForm(tester, buildScanner: _fakeScanner);
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();
      await tester.tap(find.text('emit-isbn'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '9780140449136'), findsOneWidget);
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('edit: "Look up" brings nothing but a cover address: the '
        'question', (tester) async {
      await openForm(
        tester,
        book: await seedFullEntry(),
        lookup: const LookupFound(
          BookMetadata(
            isbn: '9780140449136',
            coverUrl: 'https://books.google.com/books/content?id=x',
          ),
        ),
      );
      await tester.tap(find.byTooltip('Look up details'));
      await tester.pumpAndSettle();
      await letSnackBarExpire(tester);
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('edit: "Look up" finds nothing: no change, Back leaves', (
      tester,
    ) async {
      await openForm(tester, book: await seedFullEntry());
      await tester.tap(find.byTooltip('Look up details'));
      await tester.pumpAndSettle();
      expect(find.text('No details found for that ISBN.'), findsOneWidget);
      await letSnackBarExpire(tester);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });
  });

  testWidgets('Back while the save runs does nothing; the form then leaves '
      'by itself, with no question (D95)', (tester) async {
    await openForm(tester);
    await tester.enterText(title, 'Dune');
    repo.holdInsert = Completer<void>();
    await tapSaveAndHold(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pressSystemBack(tester, settle: false);
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsOneWidget, reason: 'Back waits for the save');

    repo.holdInsert!.complete();
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(repo.books, hasLength(1));
  });

  testWidgets('after a save that failed, Back asks', (tester) async {
    repo.insertFailure = const StorageFailure('synthetic');
    await openForm(tester);
    await tester.enterText(title, 'Dune');
    await tapSaveAndHold(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save the entry. Please try again.'),
      findsOneWidget,
    );
    await pressSystemBack(tester);

    expectAsked();
  });

  // The form reloads the wishlist between its save and leaving the screen.
  // In that moment the entry IS saved.
  testWidgets('Back in the moment of the list reload after a good save: the '
      'form leaves, no question, and the entry is there once', (tester) async {
    await openForm(tester);
    await keepWishlistLoaded(tester);
    await tester.enterText(title, 'Dune');
    repo.holdGetAll = Completer<void>();
    await tapSaveAndHold(tester);
    expect(repo.books, hasLength(1), reason: 'the save is through');
    expect(page, findsOneWidget, reason: 'the reload is held open');

    await pressSystemBack(tester);
    expectGoneWithoutQuestion();

    repo.holdGetAll!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectGoneWithoutQuestion();
    expect(repo.books, hasLength(1));
  });

  testWidgets('a letter typed in the moment of the list reload, then Back: '
      'still no question (the entry is saved)', (tester) async {
    await openForm(tester);
    await keepWishlistLoaded(tester);
    await tester.enterText(title, 'Dune');
    repo.holdGetAll = Completer<void>();
    await tapSaveAndHold(tester);
    expect(repo.books, hasLength(1), reason: 'the save is through');

    await tester.enterText(title, 'Dune, and more');
    await pressSystemBack(tester);
    expectGoneWithoutQuestion();

    repo.holdGetAll!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectGoneWithoutQuestion();
    expect(repo.books, hasLength(1));
  });
}
