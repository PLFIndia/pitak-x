import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

// N10-d part 2: the list's read intent and window are small Value Objects;
// their normalisation is what lets the controller tell "same list, reload to
// depth" from "different list, start over" (D2-b).
void main() {
  group('LibraryQuery', () {
    test('normalises text (trim) and language (trim, blank → null)', () {
      final q = LibraryQuery(
        text: '  gandhi ',
        sort: LibrarySort.recentlyAdded,
        language: '  ',
      );
      expect(q.text, 'gandhi');
      expect(q.isSearch, isTrue);
      expect(q.language, isNull);
      final l = LibraryQuery(
        sort: LibrarySort.languageAsc,
        language: ' Hindi ',
      );
      expect(l.language, 'Hindi');
      expect(l.text, '');
      expect(l.isSearch, isFalse);
    });

    test('sameIntentAs: equal after normalisation, false on any difference '
        'or against null', () {
      final a = LibraryQuery(
        text: 'x ',
        sort: LibrarySort.ageGroupAsc,
        language: 'Hindi',
      );
      final b = LibraryQuery(
        text: ' x',
        sort: LibrarySort.ageGroupAsc,
        language: ' Hindi',
      );
      expect(a.sameIntentAs(b), isTrue);
      expect(a.sameIntentAs(null), isFalse);
      expect(
        a.sameIntentAs(
          LibraryQuery(
            text: 'x',
            sort: LibrarySort.recentlyAdded,
            language: 'Hindi',
          ),
        ),
        isFalse,
        reason: 'sort differs',
      );
      expect(
        a.sameIntentAs(LibraryQuery(text: 'x', sort: LibrarySort.ageGroupAsc)),
        isFalse,
        reason: 'facet differs',
      );
      expect(
        a.sameIntentAs(
          LibraryQuery(
            text: 'y',
            sort: LibrarySort.ageGroupAsc,
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
        LibraryQuery(sort: LibrarySort.recentlyAdded).toString(),
        contains('LibraryQuery'),
      );
      expect(
        LibraryQuery(
          sort: LibrarySort.recentlyAdded,
          kind: ItemKind.other,
          periodicalUid: 'p-1',
        ).toString(),
        allOf(contains('kind: ItemKind.other'), contains('periodicalUid: p-1')),
      );
    });

    // ADR 0013 U1/U2: the kind chip and the series page are two more facets
    // of the SAME read intent — one query value, one repository read.
    test('kind defaults to null (every kind) and takes part in the intent', () {
      final all = LibraryQuery(sort: LibrarySort.recentlyAdded);
      final mags = LibraryQuery(
        sort: LibrarySort.recentlyAdded,
        kind: ItemKind.magazineIssue,
      );
      expect(all.kind, isNull);
      expect(mags.kind, ItemKind.magazineIssue);
      expect(all.sameIntentAs(mags), isFalse, reason: 'kind differs');
      expect(
        mags.sameIntentAs(
          LibraryQuery(
            sort: LibrarySort.recentlyAdded,
            kind: ItemKind.magazineIssue,
          ),
        ),
        isTrue,
      );
    });

    test('periodicalUid is trimmed, blank → null, and part of the intent', () {
      final series = LibraryQuery(
        sort: LibrarySort.recentlyAdded,
        periodicalUid: ' p-1 ',
      );
      expect(series.periodicalUid, 'p-1');
      expect(
        LibraryQuery(
          sort: LibrarySort.recentlyAdded,
          periodicalUid: '  ',
        ).periodicalUid,
        isNull,
      );
      expect(
        series.sameIntentAs(
          LibraryQuery(sort: LibrarySort.recentlyAdded, periodicalUid: 'p-1'),
        ),
        isTrue,
      );
      expect(
        series.sameIntentAs(
          LibraryQuery(sort: LibrarySort.recentlyAdded, periodicalUid: 'p-2'),
        ),
        isFalse,
      );
      expect(
        series.sameIntentAs(LibraryQuery(sort: LibrarySort.recentlyAdded)),
        isFalse,
      );
    });
  });

  group('CatalogueItemPage / LibraryWindow', () {
    const dune = CatalogueItem(id: 1, title: 'Dune');

    test('CatalogueItemPage.empty is terminal', () {
      expect(CatalogueItemPage.empty.items, isEmpty);
      expect(CatalogueItemPage.empty.hasMore, isFalse);
      expect(CatalogueItemPage.empty.toString(), contains('0 items'));
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
