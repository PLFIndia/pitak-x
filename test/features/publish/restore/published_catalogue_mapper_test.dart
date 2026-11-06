import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper.dart';
import 'package:pitaka/features/publish/application/restore/published_restore_covers.dart';

PublishedCatalogueItem _item(
  String title, {
  PublishedItemKind kind = PublishedItemKind.book,
  String? isbn,
  String? coverUrl,
  PublishedIssueDetails? issue,
}) => PublishedCatalogueItem(
  sourceIndex: 0,
  title: title,
  kind: kind,
  author: 'Author',
  isbn: isbn,
  publisher: 'Publisher',
  publishedYear: 2024,
  genre: 'Genre',
  language: 'en',
  coverUrl: coverUrl,
  ageGroup: AgeGroup.above6,
  issue: issue,
);

PublishedPeriodical _series({String? coverUrl}) => PublishedPeriodical(
  periodicalUid: 'series-uid',
  title: 'Series',
  issn: '0027-9358',
  publisher: 'Publisher',
  language: 'en',
  coverUrl: coverUrl,
);

PublishedCatalogue _catalogue({
  List<PublishedCatalogueItem> items = const [],
  List<PublishedPeriodical> periodicals = const [],
  int version = 1,
  PublishedCatalogueWarnings warnings = const PublishedCatalogueWarnings(),
}) => PublishedCatalogue(
  declaredSchemaVersion: version,
  items: items,
  periodicals: periodicals,
  warnings: warnings,
);

void main() {
  test('maps every kind, preserves series UID and degrades orphan issues', () {
    final result = mapPublishedCatalogueForRestore(
      _catalogue(
        items: [
          _item('Book', isbn: '123'),
          _item('Other', kind: PublishedItemKind.other),
          _item(
            'Issue',
            kind: PublishedItemKind.magazineIssue,
            issue: const PublishedIssueDetails(
              periodicalUid: 'series-uid',
              issueNumber: 2,
            ),
          ),
          _item(
            'Orphan',
            kind: PublishedItemKind.magazineIssue,
            issue: const PublishedIssueDetails(
              periodicalUid: 'missing',
              issueNumber: 1,
            ),
          ),
        ],
        periodicals: [_series()],
      ),
      addedDate: 42,
    ).toNullable()!;

    expect(result.payload.items, hasLength(4));
    expect(result.payload.items[0].author, 'Author');
    expect(result.payload.items[1].details, isA<OtherItemOf>());
    expect(result.payload.items[1].author, isNull);
    expect(result.payload.items[2].issue?.periodicalUid, 'series-uid');
    expect(result.payload.items[3].details, isNull);
    expect(result.issuesFiledAsBooks, 1);
    expect(result.payload.periodicals.single.periodicalUid, 'series-uid');
    expect(result.payload.items.every((item) => item.itemUid == null), isTrue);
    expect(result.payload.items.every((item) => item.addedDate == 42), isTrue);
  });

  test(
    'same-site covers become jpg leaves and pruning nulls items and series',
    () {
      final mapped = mapPublishedCatalogueForRestore(
        _catalogue(
          items: [
            _item('Book', coverUrl: 'covers/source.png'),
            _item('Remote', coverUrl: 'https://covers.openlibrary.org/a.jpg'),
          ],
          periodicals: [_series(coverUrl: 'covers/series.webp')],
        ),
        addedDate: 1,
      ).toNullable()!;

      expect(mapped.coverSources, {
        'restore-0.jpg': 'covers/series.webp',
        'restore-1.jpg': 'covers/source.png',
      });
      expect(mapped.thirdPartyCoverLinks, 1);
      final pruned = retainPublishedCovers(mapped, {'restore-1.jpg'});
      expect(pruned.payload.items[0].coverUrl, 'covers/restore-1.jpg');
      expect(pruned.payload.items[1].coverUrl, startsWith('https://'));
      expect(pruned.payload.periodicals.single.coverUrl, isNull);
      expect(
        retainPublishedCovers(mapped, {}).payload.items[0].coverUrl,
        isNull,
      );
    },
  );

  test('reader drops and invalid local rows are counted, not parse errors', () {
    final mapped = mapPublishedCatalogueForRestore(
      _catalogue(
        items: [
          _item(
            'Invalid issue',
            kind: PublishedItemKind.magazineIssue,
            issue: const PublishedIssueDetails(periodicalUid: 'series-uid'),
          ),
          _item('Valid'),
        ],
        periodicals: [_series()],
        warnings: const PublishedCatalogueWarnings(
          droppedItems: 2,
          invalidOptionalFields: 3,
        ),
      ),
      addedDate: 1,
    ).toNullable()!;

    expect(mapped.droppedRows, 3);
    expect(mapped.droppedFields, 3);
    expect(mapped.payload.parseErrors, isEmpty);
    expect(mapped.payload.items.single.title, 'Valid');
  });

  test('newer schemas refuse instead of losing unknown fields', () {
    final result = mapPublishedCatalogueForRestore(
      _catalogue(items: [_item('Book')], version: 99),
      addedDate: 1,
    );
    expect(result.swap().toNullable(), isA<SchemaTooNewFailure>());
  });

  test('unknown kinds refuse instead of becoming Other items', () {
    final result = mapPublishedCatalogueForRestore(
      _catalogue(
        items: [_item('Future', kind: PublishedItemKind.unknown)],
        warnings: const PublishedCatalogueWarnings(unknownKindItems: 1),
      ),
      addedDate: 1,
    );
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });

  test('truncation refuses the whole restore', () {
    final result = mapPublishedCatalogueForRestore(
      _catalogue(
        items: [_item('Book')],
        warnings: const PublishedCatalogueWarnings(itemsTruncated: true),
      ),
      addedDate: 1,
    );
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });

  test('canonical duplicate series refuse last-valid-wins data loss', () {
    final result = mapPublishedCatalogueForRestore(
      _catalogue(
        items: [_item('Book')],
        periodicals: [_series()],
        warnings: const PublishedCatalogueWarnings(duplicateSeriesUids: 1),
      ),
      addedDate: 1,
    );
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });

  test('an empty readable payload is refused', () {
    final result = mapPublishedCatalogueForRestore(_catalogue(), addedDate: 1);
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });
}
