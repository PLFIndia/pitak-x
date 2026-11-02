import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_availability_merge.dart';

/// SPECIFICATION of the native viewer's ONE per-item availability rule
/// (ADR 0019 Decision 4 and its S7 clarification, plan J10/A.6 #68).
///
/// The rule must: tag only books and issues; use the file only when it is
/// bound to the catalogue by an equal `keySet`; decide a keyed item from the
/// file; leave every other item with its inline tag; count the summary; and
/// show a time only when the file's `asOf` is plausible.
void main() {
  const keySet = '5e0c1d2b3a497f68';
  const now = 1762000000000;
  const asOf = 1761984300000;

  PublishedCatalogueItem item(
    int index, {
    PublishedItemKind kind = PublishedItemKind.book,
    String? key,
    PublishedAvailability? inline,
  }) => PublishedCatalogueItem(
    sourceIndex: index,
    title: 'Item $index',
    kind: kind,
    key: key,
    availability: inline,
    availabilitySource: inline == null
        ? null
        : PublishedAvailabilitySource.catalogue,
  );

  PublishedCatalogue catalogueOf(
    List<PublishedCatalogueItem> items, {
    String? catalogueKeySet = keySet,
  }) => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: items,
    periodicals: const [],
    exportedAt: 1761900000000,
    keySet: catalogueKeySet,
  );

  PublishedAvailabilityFile fileOf(
    Set<String> out, {
    String fileKeySet = keySet,
    int? fileAsOf = asOf,
  }) => PublishedAvailabilityFile(
    keySet: fileKeySet,
    outKeys: out,
    asOf: fileAsOf,
  );

  final mixed = catalogueOf([
    item(0, key: 'aaaaaaaaaaaaaaa1', inline: PublishedAvailability.available),
    item(1, key: 'aaaaaaaaaaaaaaa2', inline: PublishedAvailability.out),
    item(2, key: 'aaaaaaaaaaaaaaa3'),
    item(3, inline: PublishedAvailability.out),
    item(4, kind: PublishedItemKind.magazineIssue, key: 'aaaaaaaaaaaaaaa5'),
    item(5, kind: PublishedItemKind.other),
    item(6, kind: PublishedItemKind.unknown),
    item(7),
  ]);

  List<PublishedAvailability?> tags(PublishedCatalogueWithAvailability r) => [
    for (final entry in r.catalogue.items) entry.availability,
  ];

  group('a bound file decides every keyed book and issue', () {
    final result = PublishedAvailabilityMerge.apply(
      catalogue: mixed,
      file: fileOf({
        'aaaaaaaaaaaaaaa1',
        'aaaaaaaaaaaaaaa5',
        'ffffffffffffffff',
      }),
      nowMillis: now,
    );

    test('listed → Not available, unlisted → Available, others inline', () {
      expect(tags(result), [
        PublishedAvailability.out, // listed, overrides the inline tag
        PublishedAvailability.available, // not listed, overrides "out"
        PublishedAvailability.available, // keyed, no inline tag
        PublishedAvailability.out, // no key: inline tag
        PublishedAvailability.out, // keyed issue, listed
        null, // Other: never tagged
        null, // unknown kind: never tagged
        null, // no key, no inline tag
      ]);
    });

    test('each tag records where it came from', () {
      expect(
        [for (final entry in result.catalogue.items) entry.availabilitySource],
        [
          PublishedAvailabilitySource.availabilityFile,
          PublishedAvailabilitySource.availabilityFile,
          PublishedAvailabilitySource.availabilityFile,
          PublishedAvailabilitySource.catalogue,
          PublishedAvailabilitySource.availabilityFile,
          null,
          null,
          null,
        ],
      );
    });

    test('the summary counts tagged and available items', () {
      expect(result.usesFile, isTrue);
      expect(result.taggedCount, 5);
      expect(result.availableCount, 2);
      expect(result.hasTags, isTrue);
      expect(result.updatedAt, asOf);
    });

    test('every other field of an item is kept', () {
      final before = mixed.items.first;
      final after = result.catalogue.items.first;
      expect(after.title, before.title);
      expect(after.key, before.key);
      expect(after.sourceIndex, before.sourceIndex);
      expect(result.catalogue.keySet, keySet);
      expect(result.catalogue.exportedAt, mixed.exportedAt);
    });

    test('tagFor applies the same rule to one item', () {
      final bound = fileOf({'aaaaaaaaaaaaaaa1'});
      expect(
        PublishedAvailabilityMerge.tagFor(mixed.items[0], bound),
        PublishedAvailability.out,
      );
      expect(
        PublishedAvailabilityMerge.tagFor(mixed.items[0], null),
        PublishedAvailability.available,
      );
      expect(PublishedAvailabilityMerge.tagFor(mixed.items[5], bound), isNull);
    });
  });

  group('an unbound file is treated as missing (plan J10)', () {
    final inlineOnly = [
      PublishedAvailability.available,
      PublishedAvailability.out,
      null,
      PublishedAvailability.out,
      null,
      null,
      null,
      null,
    ];

    test('a file of another key set changes nothing', () {
      final result = PublishedAvailabilityMerge.apply(
        catalogue: mixed,
        file: fileOf({'aaaaaaaaaaaaaaa1'}, fileKeySet: '0000000000000000'),
        nowMillis: now,
      );
      expect(tags(result), inlineOnly);
      expect(result.usesFile, isFalse);
      expect(result.updatedAt, isNull);
      expect(PublishedAvailabilityMerge.isBound(mixed, fileOf({})), isTrue);
    });

    test('a catalogue without a keySet binds no file', () {
      final unbound = catalogueOf(mixed.items, catalogueKeySet: null);
      final result = PublishedAvailabilityMerge.apply(
        catalogue: unbound,
        file: fileOf({'aaaaaaaaaaaaaaa1'}),
        nowMillis: now,
      );
      expect(tags(result), inlineOnly);
      expect(PublishedAvailabilityMerge.isBound(unbound, fileOf({})), isFalse);
    });

    test('no file: the decoded catalogue object is reused as it is', () {
      // The view selects the catalogue by identity, so an unchanged result
      // never costs another query-engine pass.
      final result = PublishedAvailabilityMerge.apply(
        catalogue: mixed,
        file: null,
        nowMillis: now,
      );
      expect(result.catalogue, same(mixed));
      expect(result.taggedCount, 3);
      expect(result.availableCount, 1);
    });

    test('a bound file that agrees with every tag also reuses it', () {
      final agreeing = catalogueOf([
        const PublishedCatalogueItem(
          sourceIndex: 0,
          title: 'From the file already',
          kind: PublishedItemKind.book,
          key: 'aaaaaaaaaaaaaaa1',
          availability: PublishedAvailability.available,
          availabilitySource: PublishedAvailabilitySource.availabilityFile,
        ),
      ]);
      final result = PublishedAvailabilityMerge.apply(
        catalogue: agreeing,
        file: fileOf({}),
        nowMillis: now,
      );
      expect(result.catalogue, same(agreeing));
      expect(result.usesFile, isTrue);
    });
  });

  group('the "updated" time is shown only when plausible (AV15)', () {
    int? updatedAt(int? fileAsOf) => PublishedAvailabilityMerge.apply(
      catalogue: mixed,
      file: fileOf({}, fileAsOf: fileAsOf),
      nowMillis: now,
    ).updatedAt;

    test('a recent time is shown', () => expect(updatedAt(asOf), asOf));

    test('a missing, ancient or far-future time is not', () {
      expect(updatedAt(null), isNull);
      expect(updatedAt(1000), isNull);
      expect(updatedAt(now + 2 * 24 * 60 * 60 * 1000), isNull);
    });
  });

  test('a catalogue with no tags at all has no summary', () {
    final result = PublishedAvailabilityMerge.apply(
      catalogue: catalogueOf([item(0), item(1, kind: PublishedItemKind.other)]),
      file: null,
      nowMillis: now,
    );
    expect(result.hasTags, isFalse);
    expect(result.taggedCount, 0);
  });

  test('an empty bound file shows every keyed item as Available', () {
    // "Nothing is out" is a real answer when the library published it.
    final result = PublishedAvailabilityMerge.apply(
      catalogue: mixed,
      file: fileOf({}),
      nowMillis: now,
    );
    expect(result.catalogue.items[0].availability, isNot(isNull));
    expect(
      result.catalogue.items
          .where((entry) => entry.key != null)
          .map((entry) => entry.availability),
      everyElement(PublishedAvailability.available),
    );
  });
}
