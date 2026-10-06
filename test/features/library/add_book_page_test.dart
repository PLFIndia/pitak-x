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
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Lookup stub returning a scripted result (N02 cover/flag tests).
class _FakeLookup implements IsbnLookupService {
  _FakeLookup(this._result);
  final LookupResult _result;
  @override
  Future<LookupResult> lookupByIsbn(String isbn) async => _result;
  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async =>
      const SearchEmpty();
}

/// In-memory repo with autoincrement ids, enough to drive add + edit.
class _MemRepo implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
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
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <Book>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      BookPage(items: rows.sublist(start, end), hasMore: end < rows.length),
    );
  }

  // S34: derived from the stored books, like the real repository, so the
  // AddBookUseCase duplicate-ISBN pre-check fires in widget tests too.
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async {
    if (isbn.trim().isEmpty) return right(null);
    return right(books.where((b) => b.isbn == isbn).firstOrNull);
  }

  // Session 33: derived from the stored books, like the real repository, so
  // the Language dropdown in these tests is live.
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    final langs =
        books
            .map((b) => b.language?.trim() ?? '')
            .where((l) => l.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return right(langs);
  }

  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
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

Widget _host(_MemRepo repo, {Book? book, LookupResult? lookup}) {
  return ProviderScope(
    overrides: [
      bookRepositoryProvider.overrideWith((ref) async => repo),
      if (lookup != null)
        isbnLookupServiceProvider.overrideWithValue(_FakeLookup(lookup)),
    ],
    child: MaterialApp(home: AddBookPage(book: book)),
  );
}

/// The lookup result SnackBar overlays the form bottom for ~4s; expire it.
Future<void> _letSnackBarExpire(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
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

  // N02 regression: lookup covers used to be discarded and needsMetadata
  // could never be cleared once set.
  testWidgets('N02: an allow-listed lookup cover is saved; flag clears', (
    tester,
  ) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      title: 'Looked Up',
      coverUrl: 'https://books.google.com/books/content?id=x',
    );
    final repo = _MemRepo();
    await tester.pumpWidget(_host(repo, lookup: const LookupFound(meta)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byTooltip('Look up details'));
    await tester.pumpAndSettle();
    await _letSnackBarExpire(tester);

    await _tapSave(tester);

    expect(repo.books, hasLength(1));
    expect(
      repo.books.single.coverUrl,
      'https://books.google.com/books/content?id=x',
    );
    expect(repo.books.single.needsMetadata, isFalse);
  });

  testWidgets('N02: a NON-allow-listed lookup cover is dropped', (
    tester,
  ) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      title: 'Beacon',
      coverUrl: 'https://attacker.example/track.gif',
    );
    final repo = _MemRepo();
    await tester.pumpWidget(_host(repo, lookup: const LookupFound(meta)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byTooltip('Look up details'));
    await tester.pumpAndSettle();
    await _letSnackBarExpire(tester);

    await _tapSave(tester);

    expect(repo.books, hasLength(1));
    expect(repo.books.single.coverUrl, isNull);
  });

  testWidgets('N02: an existing cover beats the lookup cover', (tester) async {
    const meta = BookMetadata(
      isbn: '9780140449136',
      coverUrl: 'https://books.google.com/books/content?id=x',
    );
    final repo = _MemRepo();
    final existing = (await repo.insert(
      const Book(title: 'Local cover', coverUrl: 'covers/local.jpg'),
    )).getOrElse((_) => throw StateError('seed failed'));

    await tester.pumpWidget(
      _host(repo, book: existing, lookup: const LookupFound(meta)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780140449136',
    );
    await tester.tap(find.byTooltip('Look up details'));
    await tester.pumpAndSettle();
    await _letSnackBarExpire(tester);

    await _tapSave(tester);

    expect(repo.books.single.coverUrl, 'covers/local.jpg');
  });

  // N03 regression: the form used to copy the non-editable fields (cover,
  // removed flag, attribution) from the snapshot it was OPENED with. When the
  // row had changed underneath (a cover captured on the detail page), saving
  // an unrelated edit wrote the stale cover back — pointing at a file the
  // janitor had already deleted.
  testWidgets('N03: edit saves on top of the CURRENT row, not the snapshot', (
    tester,
  ) async {
    final repo = _MemRepo();
    final stale = (await repo.insert(
      const Book(title: 'Original', coverUrl: 'covers/old.jpg'),
    )).getOrElse((_) => throw StateError('seed failed'));
    // The row moved on after the snapshot was taken.
    await repo.update(
      stale.copyWith(coverUrl: 'covers/new.jpg', addedBy: 'Maintainer'),
    );

    await tester.pumpWidget(_host(repo, book: stale));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Revised',
    );
    await _tapSave(tester);

    final saved = repo.books.single;
    expect(saved.title, 'Revised');
    expect(saved.coverUrl, 'covers/new.jpg', reason: 'fresh cover kept');
    expect(saved.addedBy, 'Maintainer', reason: 'fresh attribution kept');
  });

  testWidgets('N03: editing a row that vanished shows a safe message', (
    tester,
  ) async {
    final repo = _MemRepo();
    final gone = (await repo.insert(
      const Book(title: 'Ghost'),
    )).getOrElse((_) => throw StateError('seed failed'));
    repo.books.clear();

    await tester.pumpWidget(_host(repo, book: gone));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(repo.books, isEmpty, reason: 'no resurrection by insert');
    expect(
      find.text('This book no longer exists and could not be saved.'),
      findsOneWidget,
    );
  });

  // S34 regression: a duplicate ISBN used to surface as the generic
  // "Could not save the book" — the UNIQUE index rejection was swallowed
  // into a StorageFailure. The form must now name the existing book.
  testWidgets(
    'S34: saving a duplicate ISBN says it is already in the library',
    (tester) async {
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'Dune', isbn: '9780441172719'));

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title *'),
        'Dune (second copy row)',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ISBN'),
        '9780441172719',
      );
      await _tapSave(tester);

      expect(
        find.text("'Dune' is already in your library."),
        findsOneWidget,
        reason: 'names the existing book instead of a generic save error',
      );
      expect(repo.books, hasLength(1), reason: 'nothing was inserted');
      expect(find.text('Add book'), findsWidgets, reason: 'form stayed open');
    },
  );

  testWidgets('S34: a duplicate of a REMOVED book says it is removed', (
    tester,
  ) async {
    final repo = _MemRepo();
    await repo.insert(
      const Book(title: 'Old copy', isbn: '9780441172719', removed: true),
    );

    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title *'), 'Again');
    await tester.enterText(
      find.widgetWithText(TextField, 'ISBN'),
      '9780441172719',
    );
    await _tapSave(tester);

    expect(find.textContaining('already in your library'), findsOneWidget);
    expect(find.textContaining('marked as removed'), findsOneWidget);
    expect(repo.books, hasLength(1));
  });

  // Session 33: the Language field is a dropdown of the library's languages
  // + "Other…", so a second spelling of an existing language is a deliberate
  // act, not a slip of the keyboard.
  group('Language dropdown (Session 33)', () {
    final dropdown = find.byKey(const ValueKey('language-dropdown'));
    final otherBox = find.widgetWithText(TextField, 'Other language');

    Future<void> scrollToDropdown(WidgetTester tester) =>
        tester.scrollUntilVisible(
          dropdown,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      // The menu overlay duplicates the selected item's text; `.last` is the
      // one inside the open menu.
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('empty library: offers Not set, English and Other… only', (
      tester,
    ) async {
      final repo = _MemRepo();
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();
      await scrollToDropdown(tester);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
      expect(find.text('Other…'), findsWidgets);
      expect(find.text('Hindi'), findsNothing);
      expect(otherBox, findsNothing);
    });

    testWidgets("lists the library's own languages; picking one saves it", (
      tester,
    ) async {
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'seed1', language: 'Hindi'));
      await repo.insert(const Book(title: 'seed2', language: 'Tamil'));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Title *'), 'New');
      await scrollToDropdown(tester);
      await pick(tester, 'Tamil');
      expect(otherBox, findsNothing);

      await _tapSave(tester);
      expect(repo.books.last.title, 'New');
      expect(repo.books.last.language, 'Tamil');
    });

    testWidgets('Other… reveals a text box; the typed value is saved', (
      tester,
    ) async {
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'seed', language: 'Hindi'));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Title *'), 'New');
      await scrollToDropdown(tester);
      await pick(tester, 'Other…');
      expect(otherBox, findsOneWidget);
      await tester.enterText(otherBox, 'Marathi');

      await _tapSave(tester);
      expect(repo.books.last.language, 'Marathi');
    });

    testWidgets('edit: a language not in the list shows as Other…, editable', (
      tester,
    ) async {
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'seed', language: 'Hindi'));
      // Bypass the repo list on purpose: an old-backup spelling.
      const stray = Book(id: 42, title: 'Old', language: 'Sanskrit');
      repo.books.add(stray);
      // Only `Hindi` is offered: the stray row is not in the list.
      repo.books.removeWhere((b) => b.id == 42);

      await tester.pumpWidget(_host(repo, book: stray));
      await tester.pumpAndSettle();
      await scrollToDropdown(tester);

      expect(find.text('Other…'), findsOneWidget); // the closed dropdown
      expect(otherBox, findsOneWidget);
      expect(find.text('Sanskrit'), findsOneWidget); // the box's content
    });

    testWidgets('edit: a listed language is pre-selected, no Other box', (
      tester,
    ) async {
      final repo = _MemRepo();
      final existing = (await repo.insert(
        const Book(title: 'Seed', language: 'Hindi'),
      )).getOrElse((_) => throw StateError('seed failed'));

      await tester.pumpWidget(_host(repo, book: existing));
      await tester.pumpAndSettle();
      await scrollToDropdown(tester);

      expect(find.text('Hindi'), findsOneWidget);
      expect(otherBox, findsNothing);
    });

    testWidgets('lookup: a listed language name selects it in the dropdown', (
      tester,
    ) async {
      // The lookup boundary already maps `en` → `English`; the form sees
      // the name and, since it is in the list, selects it.
      const meta = BookMetadata(isbn: '9780140449136', language: 'English');
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'seed', language: 'English'));
      await tester.pumpWidget(_host(repo, lookup: const LookupFound(meta)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ISBN'),
        '9780140449136',
      );
      await tester.tap(find.byTooltip('Look up details'));
      await tester.pumpAndSettle();
      await _letSnackBarExpire(tester);
      await scrollToDropdown(tester);

      expect(find.text('English'), findsOneWidget);
      expect(otherBox, findsNothing);
    });

    testWidgets('lookup: an unlisted language shows as Other… + text', (
      tester,
    ) async {
      const meta = BookMetadata(isbn: '9780140449136', language: 'Greek');
      final repo = _MemRepo();
      await repo.insert(const Book(title: 'seed', language: 'Hindi'));
      await tester.pumpWidget(_host(repo, lookup: const LookupFound(meta)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ISBN'),
        '9780140449136',
      );
      await tester.tap(find.byTooltip('Look up details'));
      await tester.pumpAndSettle();
      await _letSnackBarExpire(tester);
      await scrollToDropdown(tester);

      expect(otherBox, findsOneWidget);
      expect(find.text('Greek'), findsOneWidget);
    });
  });
}
