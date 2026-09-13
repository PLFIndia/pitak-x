import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

// N10-d part 2: the list's read intent and window are small Value Objects;
// their normalisation is what lets the controller tell "same list, reload to
// depth" from "different list, start over" (D2-b).
void main() {
  group('LibraryQuery', () {
    test('normalises text (trim) and language (trim, blank → null)', () {
      final q = LibraryQuery(
        text: '  gandhi ',
        sort: BookSort.recentlyAdded,
        language: '  ',
      );
      expect(q.text, 'gandhi');
      expect(q.isSearch, isTrue);
      expect(q.language, isNull);
      final l = LibraryQuery(sort: BookSort.languageAsc, language: ' Hindi ');
      expect(l.language, 'Hindi');
      expect(l.text, '');
      expect(l.isSearch, isFalse);
    });

    test('sameIntentAs: equal after normalisation, false on any difference '
        'or against null', () {
      final a = LibraryQuery(
        text: 'x ',
        sort: BookSort.ageGroupAsc,
        language: 'Hindi',
      );
      final b = LibraryQuery(
        text: ' x',
        sort: BookSort.ageGroupAsc,
        language: ' Hindi',
      );
      expect(a.sameIntentAs(b), isTrue);
      expect(a.sameIntentAs(null), isFalse);
      expect(
        a.sameIntentAs(
          LibraryQuery(
            text: 'x',
            sort: BookSort.recentlyAdded,
            language: 'Hindi',
          ),
        ),
        isFalse,
        reason: 'sort differs',
      );
      expect(
        a.sameIntentAs(LibraryQuery(text: 'x', sort: BookSort.ageGroupAsc)),
        isFalse,
        reason: 'facet differs',
      );
      expect(
        a.sameIntentAs(
          LibraryQuery(
            text: 'y',
            sort: BookSort.ageGroupAsc,
            language: 'Hindi',
          ),
        ),
        isFalse,
        reason: 'text differs',
      );
    });

    test('page-size constants: a page is smaller than the hard cap', () {
      expect(libraryPageSize, greaterThan(0));
      expect(maxLibraryPageSize, greaterThanOrEqualTo(libraryPageSize));
    });

    test('toString never throws and names the fields', () {
      expect(
        LibraryQuery(sort: BookSort.recentlyAdded).toString(),
        contains('LibraryQuery'),
      );
    });
  });

  group('BookPage / LibraryWindow', () {
    const dune = Book(id: 1, title: 'Dune');

    test('BookPage.empty is terminal', () {
      expect(BookPage.empty.items, isEmpty);
      expect(BookPage.empty.hasMore, isFalse);
      expect(BookPage.empty.toString(), contains('0 items'));
    });

    test('LibraryWindow.copyWith replaces only the given fields', () {
      const w = LibraryWindow(books: [dune], hasMore: true);
      expect(w.isLoadingMore, isFalse);
      final loading = w.copyWith(isLoadingMore: true);
      expect(loading.books, [dune]);
      expect(loading.hasMore, isTrue);
      expect(loading.isLoadingMore, isTrue);
      final done = loading.copyWith(books: const [], hasMore: false);
      expect(done.books, isEmpty);
      expect(done.hasMore, isFalse);
      expect(done.isLoadingMore, isTrue, reason: 'untouched field kept');
      expect(done.toString(), contains('hasMore: false'));
    });
  });
}
