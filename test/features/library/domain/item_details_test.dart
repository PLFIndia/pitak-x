import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

// ADR 0013 F5/D1/D4: every rule of `IssueOf.validate` at its boundary, the
// derived kind, and the field-less `OtherItemOf` marker.
void main() {
  const uid = 'p-uid-1';
  const day = 86400000;
  const jan1 = 1735689600000; // 2025-01-01T00:00:00Z

  List<String> fields(ItemDetails d) =>
      d.validate().map((e) => e.field).toList();

  group('IssueOf — kind and shape', () {
    test('kind is magazineIssue; isBound follows boundUntil', () {
      const single = IssueOf(periodicalUid: uid, issueNumber: 3);
      const bound = IssueOf(
        periodicalUid: uid,
        issueDate: jan1,
        boundUntil: jan1,
      );
      expect(single.kind, ItemKind.magazineIssue);
      expect(single.isBound, isFalse);
      expect(bound.isBound, isTrue);
    });

    test('a numbered issue, a dated issue and a bound volume are valid', () {
      expect(
        const IssueOf(periodicalUid: uid, issueNumber: 1).validate(),
        isEmpty,
      );
      expect(
        const IssueOf(periodicalUid: uid, issueDate: jan1).validate(),
        isEmpty,
      );
      expect(
        const IssueOf(
          periodicalUid: uid,
          volume: 249,
          issueNumber: 10,
          issueDate: jan1,
          label: 'Dasara special',
        ).validate(),
        isEmpty,
      );
      expect(
        const IssueOf(
          periodicalUid: uid,
          issueDate: jan1,
          boundUntil: jan1 + 364 * day,
        ).validate(),
        isEmpty,
      );
    });
  });

  group('IssueOf.validate — periodicalUid', () {
    test('blank is required', () {
      expect(fields(const IssueOf(periodicalUid: '  ', issueNumber: 1)), [
        'issue.periodicalUid',
      ]);
    });

    test('the catalogue gate trims the link and is idempotent', () {
      const item = CatalogueItem(
        title: 'Issue',
        details: IssueOf(periodicalUid: '  పత్రिक-१  ', issueNumber: 1),
      );
      final validated = CatalogueItem.validate(item).toNullable()!;
      expect(validated.issue!.periodicalUid, item.issue!.periodicalUid.trim());
      expect(validated.issue!.issueNumber, 1);
      expect(CatalogueItem.validate(validated).toNullable(), same(validated));
    });

    test('over the field cap is rejected', () {
      final long = 'u' * (CatalogueRules.maxFieldChars + 1);
      expect(fields(IssueOf(periodicalUid: long, issueNumber: 1)), [
        'issue.periodicalUid',
      ]);
      final atCap = 'u' * CatalogueRules.maxFieldChars;
      expect(fields(IssueOf(periodicalUid: atCap, issueNumber: 1)), isEmpty);
    });
  });

  group('IssueOf.validate — numbers', () {
    test('volume and issueNumber must be at least 1 when given', () {
      expect(
        fields(const IssueOf(periodicalUid: uid, volume: 0, issueNumber: 1)),
        ['issue.volume'],
      );
      expect(fields(const IssueOf(periodicalUid: uid, issueNumber: 0)), [
        'issue.issueNumber',
      ]);
      expect(fields(const IssueOf(periodicalUid: uid, issueNumber: -5)), [
        'issue.issueNumber',
      ]);
      expect(
        fields(const IssueOf(periodicalUid: uid, volume: 1, issueNumber: 1)),
        isEmpty,
      );
    });

    test('a single issue needs an issue number or a date (D6)', () {
      expect(fields(const IssueOf(periodicalUid: uid)), ['issue.issueNumber']);
      expect(fields(const IssueOf(periodicalUid: uid, volume: 2)), [
        'issue.issueNumber',
      ]);
    });
  });

  group('IssueOf.validate — dates', () {
    test('issueDate and boundUntil must be representable', () {
      const bad = CatalogueRules.maxDateMillis + 1;
      expect(fields(const IssueOf(periodicalUid: uid, issueDate: bad)), [
        'issue.issueDate',
      ]);
      expect(fields(const IssueOf(periodicalUid: uid, issueDate: -1)), [
        'issue.issueDate',
      ]);
      expect(
        fields(
          const IssueOf(periodicalUid: uid, issueDate: jan1, boundUntil: bad),
        ),
        ['issue.boundUntil'],
      );
      // 0 is the "unset" sentinel for dates elsewhere; here it is a date too.
      expect(fields(const IssueOf(periodicalUid: uid, issueDate: 0)), isEmpty);
    });

    test('a bound volume needs its first issue date', () {
      expect(fields(const IssueOf(periodicalUid: uid, boundUntil: jan1)), [
        'issue.issueDate',
      ]);
    });

    test('a bound volume may not run backwards; same day is allowed (D4)', () {
      expect(
        fields(
          const IssueOf(
            periodicalUid: uid,
            issueDate: jan1,
            boundUntil: jan1 - 1,
          ),
        ),
        ['issue.boundUntil'],
      );
      expect(
        fields(
          const IssueOf(periodicalUid: uid, issueDate: jan1, boundUntil: jan1),
        ),
        isEmpty,
      );
      expect(
        fields(
          const IssueOf(
            periodicalUid: uid,
            issueDate: jan1,
            boundUntil: jan1 + day,
          ),
        ),
        isEmpty,
      );
    });

    test('an unrepresentable end date reports one error, not two', () {
      const bad = CatalogueRules.maxDateMillis + 1;
      expect(
        fields(
          const IssueOf(periodicalUid: uid, issueDate: bad, boundUntil: jan1),
        ),
        ['issue.issueDate'],
      );
    });

    test('a bound volume needs no issue number', () {
      expect(
        fields(
          const IssueOf(periodicalUid: uid, issueDate: jan1, boundUntil: jan1),
        ),
        isEmpty,
      );
    });
  });

  group('IssueOf.validate — label', () {
    test('label over the field cap is rejected', () {
      final long = 'l' * (CatalogueRules.maxFieldChars + 1);
      expect(fields(IssueOf(periodicalUid: uid, issueNumber: 1, label: long)), [
        'issue.label',
      ]);
    });

    test('every error is reported at once', () {
      final errors = const IssueOf(
        periodicalUid: '',
        volume: 0,
        issueNumber: 0,
        issueDate: -1,
      ).validate();
      expect(
        errors.map((e) => e.field),
        containsAll([
          'issue.periodicalUid',
          'issue.volume',
          'issue.issueNumber',
          'issue.issueDate',
        ]),
      );
      // Every issue field has a user-facing label (no raw field names).
      for (final e in errors) {
        expect(e.userMessage, isNot(startsWith('issue.')));
      }
    });
  });

  group('IssueOf — copyWith and sameAs', () {
    test('copyWith replaces only the given fields', () {
      const base = IssueOf(periodicalUid: uid, volume: 1, issueNumber: 2);
      final edited = base.copyWith(issueNumber: 3, label: 'x');
      expect(edited.periodicalUid, uid);
      expect(edited.volume, 1);
      expect(edited.issueNumber, 3);
      expect(edited.label, 'x');
      expect(base.issueNumber, 2);
    });

    test('sameAs compares every field; other kinds and null differ', () {
      const a = IssueOf(periodicalUid: uid, volume: 1, issueNumber: 2);
      const b = IssueOf(periodicalUid: uid, volume: 1, issueNumber: 2);
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(b.copyWith(label: 'x')), isFalse);
      expect(a.sameAs(b.copyWith(issueDate: jan1)), isFalse);
      expect(a.sameAs(const OtherItemOf()), isFalse);
      expect(a.sameAs(null), isFalse);
    });

    test('toString carries no surprises (debug aid only)', () {
      expect(
        const IssueOf(periodicalUid: uid, issueNumber: 2).toString(),
        contains('IssueOf(p-uid-1'),
      );
    });
  });

  group('OtherItemOf', () {
    test('is the other kind, has no rules and every marker is the same', () {
      const o = OtherItemOf();
      expect(o.kind, ItemKind.other);
      expect(o.validate(), isEmpty);
      expect(o.sameAs(const OtherItemOf()), isTrue);
      expect(o.sameAs(const IssueOf(periodicalUid: uid)), isFalse);
      expect(o.sameAs(null), isFalse);
      expect(o.toString(), 'OtherItemOf()');
    });
  });

  test('CatalogueRules.isValidDateOrder', () {
    expect(CatalogueRules.isValidDateOrder(null, null), isTrue);
    expect(CatalogueRules.isValidDateOrder(jan1, null), isTrue);
    expect(CatalogueRules.isValidDateOrder(null, jan1), isTrue);
    expect(CatalogueRules.isValidDateOrder(jan1, jan1), isTrue);
    expect(CatalogueRules.isValidDateOrder(jan1, jan1 + 1), isTrue);
    expect(CatalogueRules.isValidDateOrder(jan1 + 1, jan1), isFalse);
  });
}
