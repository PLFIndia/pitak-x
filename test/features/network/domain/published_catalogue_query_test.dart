import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';

/// The pure query engine (viewer plan S3, ADR 0015 V8/V9). Every rule is a
/// pure function of (catalogue, query), so each one is asserted directly here:
/// search fields, filters, facets, the three stable sorts, and grouping.
void main() {
  PublishedCatalogueItem item(
    int index, {
    String? title,
    PublishedItemKind kind = PublishedItemKind.book,
    String? language,
    String? author,
    String? genre,
    String? isbn,
    String? transliteration,
    AgeGroup? ageGroup,
    PublishedIssueDetails? issue,
  }) => PublishedCatalogueItem(
    sourceIndex: index,
    title: title ?? 'Item $index',
    kind: kind,
    language: language,
    author: author,
    genre: genre,
    isbn: isbn,
    titleTransliteration: transliteration,
    ageGroup: ageGroup,
    issue: issue,
  );

  PublishedCatalogue catalogueOf(
    List<PublishedCatalogueItem> items, {
    List<PublishedPeriodical> periodicals = const [],
  }) => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: items,
    periodicals: periodicals,
  );

  PublishedCatalogueView run(
    PublishedCatalogue catalogue, [
    PublishedCatalogueQuery query = const PublishedCatalogueQuery(),
  ]) => PublishedQueryEngine.apply(catalogue, query);

  List<PublishedCatalogueItem> itemsOf(PublishedCatalogueView view) => [
    for (final entry in view.entries)
      if (entry is PublishedItemEntry) entry.item,
  ];

  group('search', () {
    final catalogue = catalogueOf([
      item(0, title: 'The Water Margin', author: "Shi Nai'an"),
      item(1, title: 'മലയാളം കഥ', transliteration: 'Malayalam Story'),
      item(2, title: 'Classics Anthology', genre: 'Poetry'),
      item(3, title: 'Numbered', isbn: '9780140447194'),
      item(4, title: 'Unrelated'),
    ]);

    test('matches every public search field', () {
      expect(
        itemsOf(
          run(catalogue, const PublishedCatalogueQuery(search: 'water')),
        ).single.title,
        'The Water Margin',
      );
      expect(
        itemsOf(
          run(catalogue, const PublishedCatalogueQuery(search: 'shi')),
        ).single.title,
        'The Water Margin',
      );
      expect(
        itemsOf(
          run(catalogue, const PublishedCatalogueQuery(search: 'malayalam')),
        ).single.title,
        'മലയാളം കഥ',
      );
      expect(
        itemsOf(
          run(catalogue, const PublishedCatalogueQuery(search: 'poetry')),
        ).single.title,
        'Classics Anthology',
      );
      expect(
        itemsOf(
          run(
            catalogue,
            const PublishedCatalogueQuery(search: '9780140447194'),
          ),
        ).single.title,
        'Numbered',
      );
    });

    test('is case-insensitive and trims the query', () {
      expect(
        itemsOf(
          run(catalogue, const PublishedCatalogueQuery(search: '  WATER  ')),
        ),
        hasLength(1),
      );
    });

    test('a blank query returns everything', () {
      final view = run(catalogue, const PublishedCatalogueQuery(search: '   '));
      expect(view.shownItems, 5);
      expect(view.entries, hasLength(5));
    });

    test('no match yields an empty view without touching the total', () {
      final view = run(
        catalogue,
        const PublishedCatalogueQuery(search: 'zzz-not-there'),
      );
      expect(view.hasNoMatches, isTrue);
      expect(view.shownItems, 0);
      expect(view.totalItems, 5);
    });

    test('private/excluded sentinels cannot match (hostile payload)', () {
      final decoded = const PublishedCatalogueCodec()
          .decode(
            File(
              'test/fixtures/published_catalogue/hostile_privacy.json',
            ).readAsBytesSync(),
          )
          .toNullable()!;
      for (final needle in <String>[
        'SENTINEL-NOTES',
        'SENTINEL-LOCATION',
        'SENTINEL-SOURCE',
        'SENTINEL-ADDED-BY',
        'SENTINEL-ISBN',
        'SENTINEL-PERIODICAL',
      ]) {
        expect(
          run(decoded, PublishedCatalogueQuery(search: needle)).shownItems,
          0,
          reason: 'excluded field "$needle" must not be searchable',
        );
      }
    });
  });

  group('filters', () {
    final catalogue = catalogueOf([
      item(0, title: 'Book EN', language: 'English'),
      item(
        1,
        title: 'Issue EN',
        kind: PublishedItemKind.magazineIssue,
        language: 'english ',
      ),
      item(
        2,
        title: 'Other KN',
        kind: PublishedItemKind.other,
        language: 'Kannada',
      ),
      item(
        3,
        title: 'Future FR',
        kind: PublishedItemKind.unknown,
        language: 'French',
      ),
      item(4, title: 'No Language'),
    ]);

    test('kind chips select exactly their kind', () {
      expect(
        itemsOf(
          run(
            catalogue,
            const PublishedCatalogueQuery(kind: PublishedKindFilter.books),
          ),
        ).map((i) => i.title),
        // `No Language` carries no kind key either: absent means book.
        ['Book EN', 'No Language'],
      );
      expect(
        itemsOf(
          run(
            catalogue,
            const PublishedCatalogueQuery(kind: PublishedKindFilter.magazines),
          ),
        ).map((i) => i.title),
        ['Issue EN'],
      );
      expect(
        itemsOf(
          run(
            catalogue,
            const PublishedCatalogueQuery(kind: PublishedKindFilter.others),
          ),
        ).map((i) => i.title),
        ['Other KN'],
      );
    });

    test('unknown kinds appear only under All', () {
      final all = itemsOf(run(catalogue));
      expect(all.map((i) => i.title), contains('Future FR'));
      for (final filter in <PublishedKindFilter>[
        PublishedKindFilter.books,
        PublishedKindFilter.magazines,
        PublishedKindFilter.others,
      ]) {
        expect(
          itemsOf(
            run(catalogue, PublishedCatalogueQuery(kind: filter)),
          ).map((i) => i.title),
          isNot(contains('Future FR')),
        );
      }
    });

    test('language filtering is case-insensitive and trim-tolerant', () {
      final view = run(
        catalogue,
        const PublishedCatalogueQuery(language: 'ENGLISH'),
      );
      expect(view.shownItems, 2);
    });

    test('language facets are distinct, trimmed, case-insensitive, sorted', () {
      expect(PublishedQueryEngine.languagesOf(catalogue), [
        'English',
        'French',
        'Kannada',
      ]);
    });

    test('blank languages never create a blank facet', () {
      expect(
        PublishedQueryEngine.languagesOf(
          catalogueOf([item(0, language: '  '), item(1)]),
        ),
        isEmpty,
      );
    });

    test('facets are unmodifiable', () {
      expect(
        () => PublishedQueryEngine.languagesOf(catalogue).add('x'),
        throwsUnsupportedError,
      );
    });
  });

  group('sort', () {
    test('published order is the default and uses sourceIndex', () {
      final view = run(
        catalogueOf([
          item(7, title: 'seven'),
          item(2, title: 'two'),
          item(5, title: 'five'),
        ]),
      );
      expect(itemsOf(view).map((i) => i.title), ['two', 'five', 'seven']);
    });

    test('language sort puts blanks last, then A→Z, ties by sourceIndex', () {
      final view = run(
        catalogueOf([
          item(0, title: 'blank-a', language: ''),
          item(1, title: 'zulu', language: 'Zulu'),
          item(2, title: 'alpha-2', language: 'Alpha'),
          item(3, title: 'alpha-1', language: 'alpha '),
          item(4, title: 'blank-b'),
        ]),
        const PublishedCatalogueQuery(sort: PublishedSortOrder.language),
      );
      expect(itemsOf(view).map((i) => i.title), [
        // `Alpha` and `alpha ` both normalize to "alpha": the tie falls back
        // to the published order (sourceIndex 2 before 3).
        'alpha-2',
        'alpha-1',
        'zulu',
        'blank-a',
        'blank-b',
      ]);
    });

    test('age sort puts unset last and honours the shared rank', () {
      final view = run(
        catalogueOf([
          item(0, title: 'unset'),
          item(1, title: 'advanced', ageGroup: AgeGroup.advanced),
          item(2, title: 'above-3', ageGroup: AgeGroup.above3),
          item(3, title: 'above-10', ageGroup: AgeGroup.above10),
        ]),
        const PublishedCatalogueQuery(sort: PublishedSortOrder.ageGroup),
      );
      expect(itemsOf(view).map((i) => i.title), [
        'above-3',
        'above-10',
        'advanced',
        'unset',
      ]);
    });

    test('sorting is stable for equal keys', () {
      final view = run(
        catalogueOf([
          item(4, title: 'a4', language: 'Hindi'),
          item(1, title: 'a1', language: 'Hindi'),
          item(9, title: 'a9', language: 'Hindi'),
        ]),
        const PublishedCatalogueQuery(sort: PublishedSortOrder.language),
      );
      expect(itemsOf(view).map((i) => i.title), ['a1', 'a4', 'a9']);
    });

    test('no sort depends on addedDate (it is not even a field)', () {
      // Structural proof: the model has no addedDate, so the UI cannot offer
      // a "Recently added" sort. The default is explicitly published order.
      final view = run(catalogueOf([item(3), item(1)]));
      expect(itemsOf(view).map((i) => i.sourceIndex), [1, 3]);
    });
  });

  group('grouping', () {
    const series = PublishedPeriodical(
      periodicalUid: 'chandamama',
      title: 'Chandamama',
    );

    PublishedCatalogueItem issue(
      int index,
      String uid, {
      int? volume,
      int? number,
      int? date,
      String? title,
    }) => item(
      index,
      title: title ?? 'Issue $index',
      kind: PublishedItemKind.magazineIssue,
      issue: PublishedIssueDetails(
        periodicalUid: uid,
        volume: volume,
        issueNumber: number,
        issueDate: date,
      ),
    );

    test('a group stands where its first visible issue appears', () {
      final view = run(
        catalogueOf(
          [
            item(0, title: 'book first'),
            issue(1, 'chandamama', number: 1, title: 'old'),
            item(2, title: 'middle'),
            issue(3, 'chandamama', number: 2, title: 'new'),
          ],
          periodicals: [series],
        ),
      );
      expect(view.entries, hasLength(3));
      expect(view.entries[0], isA<PublishedItemEntry>());
      expect(view.entries[1], isA<PublishedSeriesGroup>());
      expect(view.entries[2], isA<PublishedItemEntry>());
      final group = view.entries[1] as PublishedSeriesGroup;
      expect(group.series.title, 'Chandamama');
      expect(group.issues.map((i) => i.title), ['new', 'old']);
    });

    test('only visible issues appear inside a group', () {
      final view = run(
        catalogueOf(
          [
            issue(0, 'chandamama', number: 1, date: 1000, title: 'kept'),
            issue(
              1,
              'chandamama',
              number: 2,
              date: 2000,
              title: 'filtered out',
            ),
          ],
          periodicals: [series],
        ),
        const PublishedCatalogueQuery(search: 'kept'),
      );
      final group = view.entries.single as PublishedSeriesGroup;
      expect(group.issues.map((i) => i.title), ['kept']);
    });

    test('a series with no visible issue has no header', () {
      final view = run(
        catalogueOf([item(0, title: 'a book')], periodicals: [series]),
      );
      expect(view.entries.single, isA<PublishedItemEntry>());
    });

    test('orphan and partial issues stay plain rows', () {
      final view = run(
        catalogueOf(
          [
            issue(0, 'removed-series', number: 1, title: 'orphan'),
            item(1, title: 'no linkage', kind: PublishedItemKind.magazineIssue),
            issue(2, 'chandamama', number: 3, title: 'grouped'),
          ],
          periodicals: [series],
        ),
      );
      expect(view.entries, hasLength(3));
      expect(view.entries[0], isA<PublishedItemEntry>());
      expect((view.entries[0] as PublishedItemEntry).item.title, 'orphan');
      expect(view.entries[1], isA<PublishedItemEntry>());
      expect(view.entries[2], isA<PublishedSeriesGroup>());
    });

    test('inside a group: date desc, volume desc, number desc, nulls last', () {
      final view = run(
        catalogueOf(
          [
            issue(0, 'chandamama', title: 'no metadata'),
            issue(1, 'chandamama', date: 1000, title: 'older'),
            issue(2, 'chandamama', date: 3000, title: 'newest'),
            issue(3, 'chandamama', volume: 2, title: 'vol 2'),
            issue(4, 'chandamama', volume: 3, title: 'vol 3'),
            issue(5, 'chandamama', volume: 3, number: 9, title: 'vol 3 no 9'),
            issue(6, 'chandamama', volume: 3, number: 4, title: 'vol 3 no 4'),
          ],
          periodicals: [series],
        ),
      );
      final group = view.entries.single as PublishedSeriesGroup;
      expect(group.issues.map((i) => i.title), [
        'newest',
        'older',
        'vol 3 no 9',
        'vol 3 no 4',
        'vol 3',
        'vol 2',
        'no metadata',
      ]);
    });

    test('equal issue keys fall back to sourceIndex', () {
      final view = run(
        catalogueOf(
          [
            issue(5, 'chandamama', number: 1, title: 'second'),
            issue(2, 'chandamama', number: 1, title: 'first'),
          ],
          periodicals: [series],
        ),
      );
      final group = view.entries.single as PublishedSeriesGroup;
      expect(group.issues.map((i) => i.title), ['first', 'second']);
    });

    test('a payload without periodicals never groups', () {
      final view = run(catalogueOf([issue(0, 'chandamama', number: 1)]));
      expect(view.entries.single, isA<PublishedItemEntry>());
    });

    test('two series interleave by their first visible issue', () {
      const other = PublishedPeriodical(periodicalUid: 'other', title: 'Other');
      final view = run(
        catalogueOf(
          [
            issue(0, 'chandamama', title: 'c1'),
            issue(1, 'other', title: 'o1'),
            issue(2, 'chandamama', title: 'c2'),
          ],
          periodicals: [series, other],
        ),
      );
      expect(view.entries, hasLength(2));
      expect(
        (view.entries[0] as PublishedSeriesGroup).series.title,
        'Chandamama',
      );
      expect((view.entries[1] as PublishedSeriesGroup).series.title, 'Other');
    });
  });

  group('immutability', () {
    test('the source list and the view are never mutated', () {
      final source = [item(2), item(0)];
      final catalogue = catalogueOf(source);
      final view = run(
        catalogue,
        const PublishedCatalogueQuery(sort: PublishedSortOrder.language),
      );
      expect(source.map((i) => i.sourceIndex), [2, 0]);
      expect(
        () => view.entries.add(view.entries.first),
        throwsUnsupportedError,
      );
      expect(() => source.add(item(5)), returnsNormally);
    });

    test('the view counts match the engine output', () {
      final view = run(
        catalogueOf([item(0), item(1), item(2)]),
        const PublishedCatalogueQuery(kind: PublishedKindFilter.others),
      );
      expect(view.shownItems, 0);
      expect(view.totalItems, 3);
      expect(view.entries, isEmpty);
    });
  });
}
