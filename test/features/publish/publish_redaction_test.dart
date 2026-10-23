import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

void main() {
  CatalogueItem sample() => const CatalogueItem(
    id: 42,
    title: 'The Odyssey',
    author: 'Homer',
    isbn: '9780140449136',
    publisher: 'Penguin',
    publishedYear: 1996,
    genre: 'Epic',
    language: 'en',
    notes: 'Borrowed from Ravi — PII',
    location: 'Shelf 3B',
    sourceType: ItemSourceType.gift,
    sourceDetail: 'Gift from Ravi',
    addedDate: 1700000000000,
    addedBy: 'maintainer-x',
    needsMetadata: true,
    ageGroup: AgeGroup.above10,
    coverUrl: 'covers/abc.jpg',
  );

  test('keeps catalog fields, drops PII, applies availability', () {
    final p = redactForPublish(
      sample(),
      resolveCoverUrl: (b) => 'covers/${b.id}.jpg',
      availability: PublishItem.out,
    );
    expect(p.title, 'The Odyssey');
    expect(p.author, 'Homer');
    expect(p.isbn, '9780140449136');
    expect(p.publisher, 'Penguin');
    expect(p.publishedYear, 1996);
    expect(p.genre, 'Epic');
    expect(p.language, 'en');
    expect(p.ageGroup, 'above-10');
    expect(p.availability, PublishItem.out);
    // Cover resolved via callback (had access to the real id).
    expect(p.coverUrl, 'covers/42.jpg');
  });

  test('redacted JSON contains no PII keys', () {
    final json = redactForPublish(
      sample(),
      resolveCoverUrl: (_) => null,
    ).toJson();
    expect(json.containsKey('notes'), isFalse);
    expect(json.containsKey('location'), isFalse);
    expect(json.containsKey('sourceType'), isFalse);
    expect(json.containsKey('sourceDetail'), isFalse);
    expect(json.containsKey('addedDate'), isFalse);
    expect(json.containsKey('addedBy'), isFalse);
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('needsMetadata'), isFalse);
    // Dropped cover ⇒ no coverUrl key.
    expect(json.containsKey('coverUrl'), isFalse);
    // Serialised string carries none of the PII values either.
    expect(json.toString(), isNot(contains('Ravi')));
    expect(json.toString(), isNot(contains('Shelf')));
  });

  group('kinds (ADR 0014 W3)', () {
    test('a book publishes kind book and no issue object', () {
      final p = redactForPublish(sample(), resolveCoverUrl: (_) => null);
      expect(p.kind, 'book');
      expect(p.issue, isNull);
      final json = p.toJson();
      expect(json['kind'], 'book');
      expect(json.containsKey('issue'), isFalse);
    });

    test('an issue publishes its public identity in a nested issue{}', () {
      const issue = IssueOf(
        periodicalUid: 'uid-1',
        volume: 249,
        issueNumber: 10,
        issueDate: 1759276800000,
        label: 'Dasara special',
      );
      final p = redactForPublish(
        const CatalogueItem(
          id: 9,
          title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
          details: issue,
        ),
        resolveCoverUrl: (_) => null,
      );
      expect(p.kind, 'magazine-issue');
      expect(p.toJson()['issue'], {
        'periodicalUid': 'uid-1',
        'volume': 249,
        'issueNumber': 10,
        'issueDate': 1759276800000,
        'label': 'Dasara special',
      });
    });

    test('a bound volume carries boundUntil (the viewer badge trigger)', () {
      const issue = IssueOf(
        periodicalUid: 'uid-1',
        issueDate: 1750000000000,
        boundUntil: 1760000000000,
      );
      final json = redactForPublish(
        const CatalogueItem(id: 9, title: 'Bound', details: issue),
        resolveCoverUrl: (_) => null,
      ).toJson();
      expect(
        (json['issue'] as Map<String, dynamic>)['boundUntil'],
        1760000000000,
      );
    });

    test('an Other publishes kind other; its notes stay local (O2)', () {
      final json = redactForPublish(
        const CatalogueItem(
          id: 9,
          title: 'Carrom board',
          notes: 'private description',
          details: OtherItemOf(),
        ),
        resolveCoverUrl: (_) => null,
      ).toJson();
      expect(json['kind'], 'other');
      expect(json.containsKey('issue'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(json.toString(), isNot(contains('private description')));
    });
  });

  group('redactPeriodicalForPublish (W3)', () {
    Periodical series() => const Periodical(
      id: 7,
      periodicalUid: 'uid-1',
      title: 'Chandamama',
      titleTransliteration: 'Chandamama',
      issn: '0577-6058',
      publisher: 'Chandamama Publications',
      language: 'Telugu',
      coverUrl: 'covers/series.jpg',
      frequency: PeriodicalFrequency.monthly,
      subscriptionStart: 1760000000000,
      subscriptionEnd: 1790000000000,
      notes: 'private series note',
      location: 'private series shelf',
      sourceType: ItemSourceType.purchased,
      sourceDetail: 'private series source',
      ageGroup: AgeGroup.above6,
      addedDate: 1700000000000,
      addedBy: 'maintainer-x',
    );

    test('keeps the public fields, through the cover callback', () {
      final p = redactPeriodicalForPublish(
        series(),
        resolveCoverUrl: (periodical) => 'covers/hashed-${periodical.id}.jpg',
      );
      expect(p.periodicalUid, 'uid-1');
      expect(p.title, 'Chandamama');
      expect(p.titleTransliteration, 'Chandamama');
      expect(p.issn, '0577-6058');
      expect(p.publisher, 'Chandamama Publications');
      expect(p.language, 'Telugu');
      expect(p.frequency, 'monthly');
      expect(p.ageGroup, 'above-6');
      expect(p.coverUrl, 'covers/hashed-7.jpg');
    });

    test('redacted JSON contains no private keys or values', () {
      final json = redactPeriodicalForPublish(
        series(),
        resolveCoverUrl: (_) => null,
      ).toJson();
      for (final key in [
        'subscriptionStart',
        'subscriptionEnd',
        'notes',
        'location',
        'sourceType',
        'sourceDetail',
        'addedDate',
        'addedBy',
        'removed',
        'removedAt',
        'id',
        'coverUrl', // dropped cover ⇒ no key
      ]) {
        expect(json.containsKey(key), isFalse, reason: 'must strip: $key');
      }
      final serialised = json.toString();
      expect(serialised, isNot(contains('private')));
      expect(serialised, isNot(contains('subscription')));
      expect(serialised, isNot(contains('maintainer')));
    });
  });
}
