import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/issue_sorter.dart';

// The issue-list ordering contract (ADR 0013 U2): date desc, volume desc,
// number desc, id desc, with a missing key after every present one.
void main() {
  CatalogueItem issue(int id, {int? date, int? volume, int? number}) =>
      CatalogueItem(
        id: id,
        title: 'i$id',
        details: IssueOf(
          periodicalUid: 'p',
          volume: volume,
          issueNumber: number,
          issueDate: date,
        ),
      );
  List<int> ids(List<CatalogueItem> items) => items.map((i) => i.id).toList();

  group('IssueSorter.sort', () {
    test('newest date first; undated last', () {
      final out = IssueSorter.sort([
        issue(1, date: 100),
        issue(2),
        issue(3, date: 300),
        issue(4, date: 200),
      ]);
      expect(ids(out), [3, 4, 1, 2]);
    });

    test('same date: volume desc, then number desc, then id desc', () {
      final out = IssueSorter.sort([
        issue(1, date: 100, volume: 1, number: 2),
        issue(2, date: 100, volume: 2, number: 1),
        issue(3, date: 100, volume: 1, number: 3),
        issue(4, date: 100, volume: 1, number: 3),
        issue(5, date: 100, volume: 1),
      ]);
      expect(ids(out), [2, 4, 3, 1, 5]);
    });

    test('a missing volume sorts after any volume at the same date', () {
      final out = IssueSorter.sort([
        issue(1, date: 100, number: 9),
        issue(2, date: 100, volume: 1, number: 1),
      ]);
      expect(ids(out), [2, 1]);
    });

    test('non-issue rows go last by id desc; input is not mutated', () {
      final input = [
        const CatalogueItem(id: 1, title: 'book'),
        issue(2, date: 5),
        const CatalogueItem(id: 3, title: 'other', details: OtherItemOf()),
      ];
      final copy = List<CatalogueItem>.of(input);
      final out = IssueSorter.sort(input);
      expect(ids(out), [2, 3, 1]);
      expect(ids(input), ids(copy));
    });

    test('the order is total: every pair of distinct rows is ordered', () {
      final rows = [
        issue(1, date: 100, volume: 1, number: 1),
        issue(2, date: 100, volume: 1, number: 1),
        issue(3),
        issue(4),
      ];
      for (final a in rows) {
        for (final b in rows) {
          if (identical(a, b)) {
            expect(IssueSorter.compare(a, b), 0);
          } else {
            expect(
              IssueSorter.compare(a, b),
              isNot(0),
              reason: '${a.id} vs ${b.id}',
            );
            expect(
              IssueSorter.compare(a, b).sign,
              -IssueSorter.compare(b, a).sign,
              reason: 'antisymmetric',
            );
          }
        }
      }
    });
  });
}
