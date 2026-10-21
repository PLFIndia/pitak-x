import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

void main() {
  group('CatalogueItem.validate (M15)', () {
    test('accepts a minimal valid book', () {
      final r = CatalogueItem.validate(const CatalogueItem(title: 'Godaan'));
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.title, 'Godaan');
    });

    test('rejects a blank title (whitespace-only)', () {
      final r = CatalogueItem.validate(const CatalogueItem(title: '   '));
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'title');
    });

    test('trims the title', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(title: '  Godaan  '),
      );
      expect(r.toNullable()!.title, 'Godaan');
    });

    test('rejects addedDate above the max date millis', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(
          title: 'A',
          addedDate: CatalogueRules.maxDateMillis + 1,
        ),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'addedDate');
    });

    test('rejects a negative addedDate; 0 stays valid (unset)', () {
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', addedDate: -1),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(const CatalogueItem(title: 'A')).isRight(),
        isTrue,
      );
    });

    test('rejects copyCount 0 and negative', () {
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', copyCount: 0),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', copyCount: -2),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(const CatalogueItem(title: 'A')).isRight(),
        isTrue,
      );
    });

    test('rejects pageCount 0; null and positive pass', () {
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', pageCount: 0),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', pageCount: 384),
        ).isRight(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(const CatalogueItem(title: 'A')).isRight(),
        isTrue,
      );
    });

    test('rejects publishedYear 0 and 10000; 1 and 9999 pass', () {
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', publishedYear: 0),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', publishedYear: 10000),
        ).isLeft(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', publishedYear: 1),
        ).isRight(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', publishedYear: 9999),
        ).isRight(),
        isTrue,
      );
    });

    test('rejects a removedAt above the max date millis', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(
          title: 'A',
          removed: true,
          removedAt: CatalogueRules.maxDateMillis + 1,
        ),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'removedAt');
    });

    test('rejects an over-cap text field (addedBy)', () {
      final r = CatalogueItem.validate(
        CatalogueItem(
          title: 'A',
          addedBy: 'x' * (CatalogueRules.maxFieldChars + 1),
        ),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'addedBy');
    });

    test('normalises a non-allow-listed remote cover URL to null', () {
      // Not a rejection: a pre-M15 database row could already carry such a
      // URL, and rejecting would make that book uneditable forever (the form
      // copies base.coverUrl verbatim). The cover is inert anyway — display
      // and publish re-check the allow-list — so it is dropped, and the
      // importer reports the drop as a warning.
      final r = CatalogueItem.validate(
        const CatalogueItem(title: 'A', coverUrl: 'https://evil.example/c.jpg'),
      );
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.coverUrl, isNull);
    });

    test('accepts allow-listed remote covers and safe local refs', () {
      expect(
        CatalogueItem.validate(
          const CatalogueItem(
            title: 'A',
            coverUrl: 'https://covers.openlibrary.org/b/id/1.jpg',
          ),
        ).isRight(),
        isTrue,
      );
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', coverUrl: 'covers/uuid-1.jpg'),
        ).isRight(),
        isTrue,
      );
      // Legacy file:// local refs stay valid (old DB rows must still edit).
      expect(
        CatalogueItem.validate(
          const CatalogueItem(
            title: 'A',
            coverUrl: 'file:///data/app/covers/x.jpg',
          ),
        ).isRight(),
        isTrue,
      );
      // Traversal / smuggling local refs are normalised away too.
      final traversal = CatalogueItem.validate(
        const CatalogueItem(title: 'A', coverUrl: 'covers/../x.jpg'),
      );
      expect(traversal.isRight(), isTrue);
      expect(traversal.toNullable()!.coverUrl, isNull);
      // Blank is normalised to null (no cover).
      expect(
        CatalogueItem.validate(
          const CatalogueItem(title: 'A', coverUrl: '   '),
        ).toNullable()!.coverUrl,
        isNull,
      );
    });

    test('collects multiple field errors at once', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(title: '  ', copyCount: 0, publishedYear: 0),
      );
      final errors = r.getLeft().toNullable()!;
      expect(errors.length, greaterThanOrEqualTo(3));
      expect(
        errors.map((e) => e.field),
        containsAll(['title', 'copyCount', 'publishedYear']),
      );
    });
  });

  // ADR 0013 F5: the kind is derived from `details`; the entity gate appends
  // the member's own rules so one ingress check covers every kind.
  group('CatalogueItem.details (item kinds)', () {
    const issue = IssueOf(periodicalUid: 'p-1', volume: 2, issueNumber: 7);

    test('no details ⇒ a book; details decide the kind', () {
      const book = CatalogueItem(title: 'A');
      const mag = CatalogueItem(title: 'A', details: issue);
      const other = CatalogueItem(title: 'A', details: OtherItemOf());
      expect(book.kind, ItemKind.book);
      expect(book.issue, isNull);
      expect(mag.kind, ItemKind.magazineIssue);
      expect(mag.issue, same(issue));
      expect(other.kind, ItemKind.other);
      expect(other.issue, isNull);
    });

    test('validate keeps the details on the normalised copy', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(title: '  Vol 2  ', details: issue),
      );
      final item = r.toNullable()!;
      expect(item.title, 'Vol 2');
      expect(item.kind, ItemKind.magazineIssue);
      expect(item.issue!.sameAs(issue), isTrue);
      // The unchanged fast path returns the same instance, details included.
      const clean = CatalogueItem(title: 'A', details: OtherItemOf());
      expect(CatalogueItem.validate(clean).toNullable(), same(clean));
    });

    test('validate appends the issue rules as issue.* field errors', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(
          title: '',
          details: IssueOf(periodicalUid: '', issueNumber: 0),
        ),
      );
      final fields = r.getLeft().toNullable()!.map((e) => e.field);
      expect(
        fields,
        containsAll(['title', 'issue.periodicalUid', 'issue.issueNumber']),
      );
    });

    test('an Other item has no extra rules', () {
      final r = CatalogueItem.validate(
        const CatalogueItem(title: 'Carrom board', details: OtherItemOf()),
      );
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.kind, ItemKind.other);
    });

    test('copyWith keeps details unless given new ones', () {
      const mag = CatalogueItem(title: 'A', details: issue);
      expect(mag.copyWith(title: 'B').kind, ItemKind.magazineIssue);
      expect(mag.copyWith(title: 'B').issue!.sameAs(issue), isTrue);
      final renumbered = mag.copyWith(details: issue.copyWith(issueNumber: 8));
      expect(renumbered.issue!.issueNumber, 8);
      expect(mag.issue!.issueNumber, 7);
    });
  });
}
