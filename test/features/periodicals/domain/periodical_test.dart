import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

// `Periodical.validate` is the ingress gate for every magazine title (ADR
// 0013 D2/D7, same contract as `CatalogueItem.validate`): reject invalid
// values, normalise the title / ISSN / cover, keep a valid row as-is.
void main() {
  const jan1 = 1735689600000; // 2025-01-01T00:00:00Z

  List<String> fields(Periodical p) => Periodical.validate(
    p,
  ).getLeft().toNullable()!.map((e) => e.field).toList();

  group('Periodical.validate', () {
    test('accepts a minimal title and returns the same instance', () {
      const p = Periodical(title: 'Chandamama');
      final r = Periodical.validate(p);
      expect(r.isRight(), isTrue);
      expect(r.toNullable(), same(p));
    });

    test('trims the title; blank title is required', () {
      expect(
        Periodical.validate(
          const Periodical(title: '  Chandamama  '),
        ).toNullable()!.title,
        'Chandamama',
      );
      expect(fields(const Periodical(title: '   ')), ['title']);
    });

    test('ISSN is normalised to canonical form; blank means none', () {
      final r = Periodical.validate(
        const Periodical(title: 'A', issn: ' 03178471 '),
      );
      expect(r.toNullable()!.issn, '0317-8471');
      expect(
        Periodical.validate(
          const Periodical(title: 'A', issn: '  '),
        ).toNullable()!.issn,
        isNull,
      );
      expect(
        Periodical.validate(
          const Periodical(title: 'A', issn: '0317-8471'),
        ).toNullable()!.issn,
        '0317-8471',
      );
    });

    test('an invalid ISSN is rejected, not coerced', () {
      expect(fields(const Periodical(title: 'A', issn: '0317-8472')), ['issn']);
      expect(fields(const Periodical(title: 'A', issn: 'abc')), ['issn']);
    });

    test('every text field is capped', () {
      final long = 'x' * (CatalogueRules.maxFieldChars + 1);
      expect(fields(Periodical(title: long)), ['title']);
      expect(fields(Periodical(title: 'A', publisher: long)), ['publisher']);
      expect(fields(Periodical(title: 'A', notes: long)), ['notes']);
      expect(fields(Periodical(title: 'A', periodicalUid: long)), [
        'periodicalUid',
      ]);
      expect(fields(Periodical(title: 'A', addedBy: long)), ['addedBy']);
    });

    test('dates must be representable', () {
      const bad = CatalogueRules.maxDateMillis + 1;
      expect(fields(const Periodical(title: 'A', addedDate: bad)), [
        'addedDate',
      ]);
      expect(fields(const Periodical(title: 'A', addedDate: -1)), [
        'addedDate',
      ]);
      expect(fields(const Periodical(title: 'A', removedAt: bad)), [
        'removedAt',
      ]);
      expect(fields(const Periodical(title: 'A', subscriptionStart: bad)), [
        'subscriptionStart',
      ]);
      expect(fields(const Periodical(title: 'A', subscriptionEnd: bad)), [
        'subscriptionEnd',
      ]);
    });

    test('the subscription window may not run backwards (same day ok)', () {
      expect(
        fields(
          const Periodical(
            title: 'A',
            subscriptionStart: jan1,
            subscriptionEnd: jan1 - 1,
          ),
        ),
        ['subscriptionEnd'],
      );
      expect(
        Periodical.validate(
          const Periodical(
            title: 'A',
            subscriptionStart: jan1,
            subscriptionEnd: jan1,
          ),
        ).isRight(),
        isTrue,
      );
      // An end without a start, or a start without an end, is fine.
      expect(
        Periodical.validate(
          const Periodical(title: 'A', subscriptionEnd: jan1),
        ).isRight(),
        isTrue,
      );
      expect(
        Periodical.validate(
          const Periodical(title: 'A', subscriptionStart: jan1),
        ).isRight(),
        isTrue,
      );
    });

    test('an unrepresentable end date reports one error, not two', () {
      const bad = CatalogueRules.maxDateMillis + 1;
      expect(
        fields(
          const Periodical(
            title: 'A',
            subscriptionStart: jan1,
            subscriptionEnd: bad,
          ),
        ),
        ['subscriptionEnd'],
      );
    });

    test('covers are normalised, never rejected (M15 rule)', () {
      expect(
        Periodical.validate(
          const Periodical(title: 'A', coverUrl: 'http://evil.test/x.jpg'),
        ).toNullable()!.coverUrl,
        isNull,
      );
      expect(
        Periodical.validate(
          const Periodical(title: 'A', coverUrl: ' covers/uuid-1.jpg '),
        ).toNullable()!.coverUrl,
        'covers/uuid-1.jpg',
      );
      expect(
        Periodical.validate(
          const Periodical(title: 'A', coverUrl: '   '),
        ).toNullable()!.coverUrl,
        isNull,
      );
    });

    test('collects every error at once', () {
      final f = fields(
        const Periodical(title: ' ', issn: 'bad', addedDate: -1),
      );
      expect(f, containsAll(['title', 'issn', 'addedDate']));
    });

    test('the normalised copy keeps every other field', () {
      const p = Periodical(
        id: 4,
        periodicalUid: 'u',
        title: ' T ',
        titleTransliteration: 'tr',
        issn: '03178471',
        publisher: 'pub',
        language: 'Telugu',
        coverUrl: 'covers/a.jpg',
        frequency: PeriodicalFrequency.monthly,
        subscriptionStart: jan1,
        subscriptionEnd: jan1 + 1,
        notes: 'n',
        location: 'shelf',
        sourceType: ItemSourceType.gift,
        sourceDetail: 'd',
        ageGroup: AgeGroup.above6,
        addedDate: jan1,
        removed: true,
        removedAt: jan1 + 2,
        addedBy: 'me',
      );
      final v = Periodical.validate(p).toNullable()!;
      expect(v.title, 'T');
      expect(v.issn, '0317-8471');
      expect(v.copyWith(title: ' T ', issn: '03178471').sameAs(p), isTrue);
      expect(v.id, 4);
      expect(v.isSubscriptionTracked, isTrue);
    });
  });

  group('Periodical.copyWith / sameAs', () {
    test('copyWith replaces only the given fields', () {
      const p = Periodical(title: 'A', publisher: 'P');
      final q = p.copyWith(title: 'B');
      expect(q.title, 'B');
      expect(q.publisher, 'P');
      expect(p.title, 'A');
    });

    test('sameAs ignores the per-device id and compares every other field', () {
      const a = Periodical(id: 1, title: 'A', issn: '0317-8471');
      const b = Periodical(id: 2, title: 'A', issn: '0317-8471');
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(b.copyWith(language: 'Hindi')), isFalse);
      expect(a.sameAs(b.copyWith(removed: true)), isFalse);
    });

    test('isSubscriptionTracked follows the end date only (D5)', () {
      expect(const Periodical(title: 'A').isSubscriptionTracked, isFalse);
      expect(
        const Periodical(
          title: 'A',
          subscriptionStart: jan1,
        ).isSubscriptionTracked,
        isFalse,
      );
      expect(
        const Periodical(
          title: 'A',
          subscriptionEnd: jan1,
        ).isSubscriptionTracked,
        isTrue,
      );
    });
  });
}
