import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// The two copy helpers the availability merge uses (ADR 0019 Decision 4):
/// [PublishedCatalogueItem.withAvailability] and
/// [PublishedCatalogue.withItems].
///
/// Why test plain copies (beginner note): a copy helper that forgets ONE
/// field silently blanks it on screen (an author vanishes as soon as a tag
/// is applied). Every field is therefore set to a distinctive value and
/// compared after the copy.
void main() {
  const issue = PublishedIssueDetails(
    periodicalUid: 'chandamama',
    volume: 249,
    issueNumber: 10,
    issueDate: 1791072000000,
    boundUntil: 1793664000000,
    label: 'Dasara special',
  );

  /// An item with EVERY field set to a value that differs from its default.
  const full = PublishedCatalogueItem(
    sourceIndex: 7,
    title: 'Title',
    kind: PublishedItemKind.magazineIssue,
    titleTransliteration: 'Translit',
    author: 'Author',
    isbn: '9780140447194',
    publisher: 'Publisher',
    publishedYear: 1976,
    genre: 'Genre',
    language: 'Kannada',
    coverUrl: 'covers/a.jpg',
    ageGroup: AgeGroup.above10,
    availability: PublishedAvailability.available,
    availabilitySource: PublishedAvailabilitySource.catalogue,
    key: 'aaaaaaaaaaaaaaa1',
    issue: issue,
  );

  /// Asserts every field except the two availability ones is unchanged.
  void expectSameFieldsExceptTag(
    PublishedCatalogueItem copy,
    PublishedCatalogueItem original,
  ) {
    expect(copy.sourceIndex, original.sourceIndex);
    expect(copy.title, original.title);
    expect(copy.kind, original.kind);
    expect(copy.titleTransliteration, original.titleTransliteration);
    expect(copy.author, original.author);
    expect(copy.isbn, original.isbn);
    expect(copy.publisher, original.publisher);
    expect(copy.publishedYear, original.publishedYear);
    expect(copy.genre, original.genre);
    expect(copy.language, original.language);
    expect(copy.coverUrl, original.coverUrl);
    expect(copy.ageGroup, original.ageGroup);
    expect(copy.key, original.key);
    expect(copy.issue, same(original.issue));
  }

  group('PublishedCatalogueItem.withAvailability', () {
    test('copies every field and sets the new tag and source', () {
      final copy = full.withAvailability(
        PublishedAvailability.out,
        PublishedAvailabilitySource.availabilityFile,
      );
      expectSameFieldsExceptTag(copy, full);
      expect(copy.availability, PublishedAvailability.out);
      expect(
        copy.availabilitySource,
        PublishedAvailabilitySource.availabilityFile,
      );
      expect(copy.isUnknownKind, isFalse);
    });

    test('never changes the original (it is a new object)', () {
      final copy = full.withAvailability(
        PublishedAvailability.out,
        PublishedAvailabilitySource.availabilityFile,
      );
      expect(copy, isNot(same(full)));
      expect(full.availability, PublishedAvailability.available);
      expect(full.availabilitySource, PublishedAvailabilitySource.catalogue);
    });

    test('a null availability forces a null source', () {
      for (final source in [
        PublishedAvailabilitySource.catalogue,
        PublishedAvailabilitySource.availabilityFile,
        null,
      ]) {
        final copy = full.withAvailability(null, source);
        expect(copy.availability, isNull, reason: '$source');
        expect(copy.availabilitySource, isNull, reason: '$source');
        expectSameFieldsExceptTag(copy, full);
      }
    });

    test('a tag without a source is recorded as from the catalogue', () {
      // The cautious claim ("at publish time"), never one of freshness.
      final copy = full.withAvailability(PublishedAvailability.out, null);
      expect(copy.availability, PublishedAvailability.out);
      expect(copy.availabilitySource, PublishedAvailabilitySource.catalogue);
    });

    test('a sparse item with no optional fields stays sparse', () {
      const sparse = PublishedCatalogueItem(
        sourceIndex: 0,
        title: 'Sparse',
        kind: PublishedItemKind.book,
      );
      final copy = sparse.withAvailability(
        PublishedAvailability.available,
        PublishedAvailabilitySource.availabilityFile,
      );
      expectSameFieldsExceptTag(copy, sparse);
      expect(copy.key, isNull);
      expect(copy.issue, isNull);
      expect(copy.availability, PublishedAvailability.available);
    });

    test('an unknown kind keeps its kind', () {
      const unknown = PublishedCatalogueItem(
        sourceIndex: 3,
        title: 'Future',
        kind: PublishedItemKind.unknown,
      );
      final copy = unknown.withAvailability(null, null);
      expect(copy.kind, PublishedItemKind.unknown);
      expect(copy.isUnknownKind, isTrue);
    });
  });

  group('PublishedCatalogue.withItems', () {
    const warnings = PublishedCatalogueWarnings(
      droppedItems: 1,
      invalidOptionalFields: 2,
      unknownKindItems: 3,
      itemsTruncated: true,
    );
    const series = PublishedPeriodical(
      periodicalUid: 'chandamama',
      title: 'Chandamama',
    );

    PublishedCatalogue catalogue({
      int version = 2,
      int? exportedAt = 1761980000000,
      String? keySet = '5e0c1d2b3a497f68',
    }) => PublishedCatalogue(
      declaredSchemaVersion: version,
      exportedAt: exportedAt,
      keySet: keySet,
      items: const [full],
      periodicals: const [series],
      warnings: warnings,
    );

    test('keeps the schema version, exportedAt, keySet, periodicals and '
        'warnings; replaces only the items', () {
      final original = catalogue();
      final tagged = full.withAvailability(
        PublishedAvailability.out,
        PublishedAvailabilitySource.availabilityFile,
      );
      final copy = original.withItems([tagged]);
      expect(copy.declaredSchemaVersion, 2);
      expect(copy.hasNewerSchema, isTrue);
      expect(copy.exportedAt, 1761980000000);
      expect(copy.keySet, '5e0c1d2b3a497f68');
      expect(copy.periodicals, hasLength(1));
      expect(copy.periodicals.single, same(series));
      expect(copy.warnings, same(warnings));
      expect(copy.items, hasLength(1));
      expect(copy.items.single, same(tagged));
      // The original still holds its own items.
      expect(original.items.single, same(full));
    });

    test('keeps null exportedAt and keySet as null', () {
      final copy = catalogue(
        version: 1,
        exportedAt: null,
        keySet: null,
      ).withItems(const [full]);
      expect(copy.declaredSchemaVersion, 1);
      expect(copy.hasNewerSchema, isFalse);
      expect(copy.exportedAt, isNull);
      expect(copy.keySet, isNull);
    });

    test('the new lists are unmodifiable copies', () {
      final source = [full];
      final copy = catalogue().withItems(source);
      // Changing the caller's list later never changes the catalogue.
      source.clear();
      expect(copy.items, hasLength(1));
      expect(() => copy.items.add(full), throwsUnsupportedError);
      expect(() => copy.periodicals.add(series), throwsUnsupportedError);
    });

    test('the derived states follow the kept warnings', () {
      final copy = catalogue().withItems(const []);
      // No readable items and a truncated/dropped source: the same "nothing
      // readable" state the original would report with no items.
      expect(copy.hasNoReadableItems, isTrue);
      expect(copy.warnings.hasPartialRead, isTrue);
      expect(copy.warnings.hasUnknownKinds, isTrue);
    });
  });
}
