import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/issue_title.dart';

// Every omission combination of (volume, number, date) for a single issue
// and (volume, from, until) for a bound volume (ADR 0013 D3).
void main() {
  int utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch;
  final oct2026 = utc(2026, 10, 1);
  final jul2025 = utc(2025, 7, 1);
  final jun2026 = utc(2026, 6, 1);

  group('IssueTitle.compose — single issue', () {
    test('volume, number and date', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(
            periodicalUid: 'u',
            volume: 249,
            issueNumber: 10,
            issueDate: oct2026,
          ),
        ),
        'Chandamama — Vol 249 No 10 (Oct 2026)',
      );
    });

    test('numbers without a date', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          const IssueOf(periodicalUid: 'u', volume: 249, issueNumber: 10),
        ),
        'Chandamama — Vol 249 No 10',
      );
      expect(
        IssueTitle.compose(
          'Chandamama',
          const IssueOf(periodicalUid: 'u', issueNumber: 10),
        ),
        'Chandamama — No 10',
      );
      expect(
        IssueTitle.compose(
          'Chandamama',
          const IssueOf(periodicalUid: 'u', volume: 249),
        ),
        'Chandamama — Vol 249',
      );
    });

    test('number and date, volume and date, date only', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(periodicalUid: 'u', issueNumber: 10, issueDate: oct2026),
        ),
        'Chandamama — No 10 (Oct 2026)',
      );
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(periodicalUid: 'u', volume: 249, issueDate: oct2026),
        ),
        'Chandamama — Vol 249 (Oct 2026)',
      );
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(periodicalUid: 'u', issueDate: oct2026),
        ),
        'Chandamama — Oct 2026',
      );
    });

    test('nothing to add ⇒ the series title alone; the title is trimmed', () {
      expect(
        IssueTitle.compose('  Chandamama ', const IssueOf(periodicalUid: 'u')),
        'Chandamama',
      );
    });

    test('month names are the fixed English list', () {
      for (var m = 1; m <= 12; m++) {
        final t = IssueTitle.compose(
          'S',
          IssueOf(periodicalUid: 'u', issueDate: utc(2026, m, 15)),
        );
        expect(t, 'S — ${IssueTitle.months[m]} 2026');
      }
      expect(IssueTitle.months.sublist(1), [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ]);
    });
  });

  group('IssueTitle.compose — bound volume', () {
    test('volume with a date range', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(
            periodicalUid: 'u',
            volume: 248,
            issueDate: jul2025,
            boundUntil: jun2026,
          ),
        ),
        'Chandamama — Vol 248, Jul 2025 – Jun 2026',
      );
    });

    test('range without a volume; numbers are kept when present', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(periodicalUid: 'u', issueDate: jul2025, boundUntil: jun2026),
        ),
        'Chandamama — Jul 2025 – Jun 2026',
      );
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(
            periodicalUid: 'u',
            volume: 248,
            issueNumber: 1,
            issueDate: jul2025,
            boundUntil: jun2026,
          ),
        ),
        'Chandamama — Vol 248 No 1, Jul 2025 – Jun 2026',
      );
    });

    test('a (malformed) bound volume without a first date still renders', () {
      expect(
        IssueTitle.compose(
          'Chandamama',
          IssueOf(periodicalUid: 'u', volume: 248, boundUntil: jun2026),
        ),
        'Chandamama — Vol 248, Jun 2026',
      );
    });
  });

  test('IssueTitle.yearOf', () {
    expect(IssueTitle.yearOf(null), isNull);
    expect(IssueTitle.yearOf(oct2026), 2026);
  });

  test(
    'a canonical UTC day has the same title and year in every host zone',
    () {
      final january = DateTime.utc(2026).millisecondsSinceEpoch;
      final issue = IssueOf(periodicalUid: 'u', issueDate: january);

      expect(IssueTitle.compose('Chandamama', issue), 'Chandamama — Jan 2026');
      expect(IssueTitle.yearOf(january), 2026);
    },
  );
}
