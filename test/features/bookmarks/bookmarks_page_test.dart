import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:pitaka/features/bookmarks/presentation/pages/bookmarks_page.dart';

class _FakeRepo implements BookmarksRepository {
  _FakeRepo(this._list);
  final List<LibraryBookmark> _list;

  @override
  Future<List<LibraryBookmark>> load() async => List.of(_list);
  @override
  Future<Either<Failure, List<LibraryBookmark>>> add(LibraryBookmark b) async {
    _list.add(b);
    return right(List.of(_list));
  }

  @override
  Future<Either<Failure, List<LibraryBookmark>>> removeAt(int i) async {
    if (i >= 0 && i < _list.length) _list.removeAt(i);
    return right(List.of(_list));
  }
}

Widget _app(List<LibraryBookmark> seed) => ProviderScope(
  overrides: [
    bookmarksRepositoryProvider.overrideWith((ref) async => _FakeRepo(seed)),
  ],
  child: const MaterialApp(home: BookmarksPage()),
);

void main() {
  testWidgets('shows the info note about accepted page types', (tester) async {
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('github.io'), findsOneWidget);
    expect(find.textContaining('pages.dev'), findsOneWidget);
    expect(find.text('No bookmarks yet.'), findsOneWidget);
  });

  testWidgets('lists saved bookmarks with their label + url', (tester) async {
    await tester.pumpWidget(
      _app([
        LibraryBookmark.create(
          label: 'Indiranagar Library',
          url: 'https://indlib.github.io/books/',
        )!,
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Indiranagar Library'), findsOneWidget);
    expect(find.text('https://indlib.github.io/books/'), findsOneWidget);
  });

  testWidgets('the add dialog rejects a non-Pages link with an error', (
    tester,
  ) async {
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add link'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Label'),
      'Some Library',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'https://example.com/',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Dialog stays open (its Add button still present) showing the inline URL
    // error; the bad link was not accepted.
    expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    // The inline URL error (mentions the accepted Pages hosts) is shown.
    expect(find.textContaining('Cloudflare Pages'), findsWidgets);
  });
}
