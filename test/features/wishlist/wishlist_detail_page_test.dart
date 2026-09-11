import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/presentation/pages/wishlist_detail_page.dart';

/// M13 widget tests: a failed purchase keeps the user on the detail page with a
/// message (retry stays possible); a successful one pops; both purchase
/// buttons are disabled while a purchase is in flight.
///
/// The book repository's `insert` is scriptable (fail / hang / succeed). The
/// wishlist repo is in-memory; its `runInTransaction` counterpart lives on the
/// book repo and is a pass-through here — rollback itself is proven with real
/// Drift in `wishlist_use_cases_test.dart`; this file covers the UI contract.
class _MemWishlistRepo implements WishlistRepository {
  _MemWishlistRepo(this.books);

  final List<WishlistBook> books;

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
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

class _ScriptedBookRepo implements BookRepository {
  /// When set, `insert` returns this failure.
  Failure? failInsertWith;

  /// When set, `insert` does not complete until this completer is completed.
  Completer<void>? insertGate;

  final List<Book> stored = [];
  int insertCalls = 0;

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    insertCalls++;
    final gate = insertGate;
    if (gate != null) await gate.future;
    final f = failInsertWith;
    if (f != null) return left(f);
    final saved = book.copyWith(id: stored.length + 1);
    stored.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async =>
      right(stored.where((b) => b.isbn == isbn).firstOrNull);
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(stored);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(stored.where((b) => b.id == id).firstOrNull);
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
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

const _entry = WishlistBook(id: 1, title: 'Wanted One', isbn: '123');

/// Hosts the detail page ABOVE a home route so `Navigator.pop()` is observable
/// (home text reappears) rather than throwing on an empty stack.
Widget _host(_MemWishlistRepo wishlist, _ScriptedBookRepo books) =>
    ProviderScope(
      overrides: [
        wishlistRepositoryProvider.overrideWith((ref) async => wishlist),
        bookRepositoryProvider.overrideWith((ref) async => books),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WishlistDetailPage(
                      bookId: _entry.id,
                      initialBook: _entry,
                    ),
                  ),
                ),
                child: const Text('open detail'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('open detail'));
  await tester.pumpAndSettle();
  expect(find.text('Wanted One'), findsOneWidget);
}

final _moveButton = find.widgetWithText(
  FilledButton,
  'Purchased — add to library',
);
final _flagButton = find.widgetWithText(
  OutlinedButton,
  'Mark as purchased only',
);

/// What the application layer does after a background write to the wishlist.
void _signalWishlistChanged(WidgetTester tester) {
  ProviderScope.containerOf(
    tester.element(find.byType(WishlistDetailPage)),
  ).invalidate(wishlistControllerProvider);
}

void main() {
  testWidgets(
    'N03: a row rewritten while the page is open is shown without re-entry',
    (tester) async {
      final wishlist = _MemWishlistRepo([_entry]);
      await tester.pumpWidget(_host(wishlist, _ScriptedBookRepo()));
      await _openDetail(tester);
      expect(find.text('Wanted'), findsOneWidget, reason: 'Status row');

      wishlist.books[0] = _entry.copyWith(
        title: 'Wanted One (2nd ed.)',
        purchased: true,
        purchasedDate: 1,
      );
      _signalWishlistChanged(tester);
      await tester.pumpAndSettle();

      expect(find.text('Wanted One (2nd ed.)'), findsOneWidget);
      expect(find.text('Wanted One'), findsNothing);
      expect(find.text('Purchased'), findsOneWidget);
      // Purchase buttons disappear because the CURRENT row is purchased.
      expect(_moveButton, findsNothing);
      expect(_flagButton, findsNothing);
    },
  );

  testWidgets('N03: an entry deleted underneath shows a safe empty state', (
    tester,
  ) async {
    final wishlist = _MemWishlistRepo([_entry]);
    await tester.pumpWidget(_host(wishlist, _ScriptedBookRepo()));
    await _openDetail(tester);

    wishlist.books.clear();
    _signalWishlistChanged(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer'), findsOneWidget);
    expect(find.text('Wanted One'), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'N03: Edit from the detail page saves on top of the CURRENT row',
    (tester) async {
      final wishlist = _MemWishlistRepo([_entry]);
      await tester.pumpWidget(_host(wishlist, _ScriptedBookRepo()));
      await _openDetail(tester);

      // The row moved on after the page was pushed (cover materialised).
      wishlist.books[0] = _entry.copyWith(coverUrl: 'covers/new.jpg');
      _signalWishlistChanged(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit wishlist item'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title *'),
        'Wanted One (revised)',
      );
      // Drop focus first: a focused field scrolls itself back into view once
      // the fling settles, which would unbuild the lazily built save button.
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

      final saved = wishlist.books.single;
      expect(saved.title, 'Wanted One (revised)');
      expect(saved.coverUrl, 'covers/new.jpg', reason: 'fresh cover kept');
      // Back on the detail page showing the edited row (no pop to the list).
      expect(find.text('Wanted One (revised)'), findsOneWidget);
      expect(find.text('open detail'), findsNothing);
    },
  );

  testWidgets(
    'M13: a failed purchase stays on the page, shows a safe message, and '
    'keeps the purchase buttons for a retry',
    (tester) async {
      final wishlist = _MemWishlistRepo([_entry]);
      final books = _ScriptedBookRepo()
        ..failInsertWith = const StorageFailure('insert: SQLITE_FULL /data');
      await tester.pumpWidget(_host(wishlist, books));
      await _openDetail(tester);

      await tester.tap(_moveButton);
      await tester.pumpAndSettle();

      // Still on the detail page, not popped back to the host.
      expect(find.text('Wanted One'), findsOneWidget);
      expect(find.text('open detail'), findsNothing);
      // Plain-language message; the raw failure text must not leak.
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(find.textContaining('SQLITE_FULL'), findsNothing);
      // Buttons are back and enabled so the user can retry.
      expect(tester.widget<FilledButton>(_moveButton).enabled, isTrue);
      expect(tester.widget<OutlinedButton>(_flagButton).enabled, isTrue);
    },
  );

  testWidgets(
    'M13: both purchase buttons are disabled while a purchase is in flight',
    (tester) async {
      final wishlist = _MemWishlistRepo([_entry]);
      final gate = Completer<void>();
      final books = _ScriptedBookRepo()..insertGate = gate;
      await tester.pumpWidget(_host(wishlist, books));
      await _openDetail(tester);

      await tester.tap(_moveButton);
      await tester.pump();
      await tester.pump(); // let the provider resolve and reach insert()

      expect(books.insertCalls, 1);
      expect(tester.widget<FilledButton>(_moveButton).enabled, isFalse);
      expect(tester.widget<OutlinedButton>(_flagButton).enabled, isFalse);

      // A second tap while busy must not start another purchase.
      await tester.tap(_flagButton, warnIfMissed: false);
      await tester.pump();
      expect(books.insertCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      // Success: popped back to the host.
      expect(find.text('open detail'), findsOneWidget);
      expect(books.stored, hasLength(1));
    },
  );

  testWidgets('M13: a successful purchase pops back to the list', (
    tester,
  ) async {
    final wishlist = _MemWishlistRepo([_entry]);
    final books = _ScriptedBookRepo();
    await tester.pumpWidget(_host(wishlist, books));
    await _openDetail(tester);

    await tester.tap(_moveButton);
    await tester.pumpAndSettle();

    expect(find.text('open detail'), findsOneWidget);
    expect(find.text('Wanted One'), findsNothing);
    expect(books.stored.single.title, 'Wanted One');
    expect(wishlist.books.single.purchased, isTrue);
  });

  testWidgets(
    'M13: an entry that turned purchased underneath pops with a notice '
    'and inserts nothing',
    (tester) async {
      final wishlist = _MemWishlistRepo([_entry]);
      final books = _ScriptedBookRepo();
      await tester.pumpWidget(_host(wishlist, books));
      await _openDetail(tester);

      // Another screen (or a second device sync) marked it purchased already.
      wishlist.books[0] = _entry.copyWith(purchased: true, purchasedDate: 1);

      await tester.tap(_moveButton);
      await tester.pumpAndSettle();

      expect(find.text('open detail'), findsOneWidget);
      expect(
        find.text('This entry was already marked purchased.'),
        findsOneWidget,
      );
      expect(books.insertCalls, 0);
    },
  );
}
