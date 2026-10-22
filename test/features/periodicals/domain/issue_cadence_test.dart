import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/issue_cadence.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

// Next-issue prefill: numbers from the latest issue, dates one cadence step
// later in LOCAL calendar time (the picker stores local-midnight instants).
void main() {
  int local(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

  group('IssueCadence.addMonthsClamped', () {
    test('keeps the day when it exists in the target month', () {
      expect(
        IssueCadence.addMonthsClamped(DateTime(2026, 1, 15), 1),
        DateTime(2026, 2, 15),
      );
      expect(
        IssueCadence.addMonthsClamped(DateTime(2026, 11, 30), 3),
        DateTime(2027, 2, 28),
      );
    });

    test(
      'clamps to the month end: 31 Jan + 1 → 28 Feb (29 in a leap year)',
      () {
        expect(
          IssueCadence.addMonthsClamped(DateTime(2026, 1, 31), 1),
          DateTime(2026, 2, 28),
        );
        expect(
          IssueCadence.addMonthsClamped(DateTime(2028, 1, 31), 1),
          DateTime(2028, 2, 29),
        );
        expect(
          IssueCadence.addMonthsClamped(DateTime(2026, 3, 31), 1),
          DateTime(2026, 4, 30),
        );
        // Clamping does not "stick": 28 Feb + 1 month is 28 March.
        expect(
          IssueCadence.addMonthsClamped(DateTime(2026, 2, 28), 1),
          DateTime(2026, 3, 28),
        );
      },
    );

    test('crosses year boundaries and keeps the time of day', () {
      expect(
        IssueCadence.addMonthsClamped(DateTime(2026, 12, 10, 8, 30), 1),
        DateTime(2027, 1, 10, 8, 30),
      );
      expect(
        IssueCadence.addMonthsClamped(DateTime(2026, 7), 12),
        DateTime(2027, 7),
      );
      expect(
        IssueCadence.addMonthsClamped(DateTime(2026, 10, 31), 24),
        DateTime(2028, 10, 31),
      );
    });
  });

  group('IssueCadence.nextDate', () {
    test('day-based cadences add exact days', () {
      expect(
        IssueCadence.nextDate(local(2026, 1, 1), PeriodicalFrequency.weekly),
        local(2026, 1, 8),
      );
      expect(
        IssueCadence.nextDate(
          local(2026, 1, 1),
          PeriodicalFrequency.fortnightly,
        ),
        local(2026, 1, 15),
      );
    });

    test('month-based cadences step calendar months with clamping', () {
      expect(
        IssueCadence.nextDate(local(2026, 1, 31), PeriodicalFrequency.monthly),
        local(2026, 2, 28),
      );
      expect(
        IssueCadence.nextDate(
          local(2026, 1, 31),
          PeriodicalFrequency.bimonthly,
        ),
        local(2026, 3, 31),
      );
      expect(
        IssueCadence.nextDate(
          local(2026, 1, 31),
          PeriodicalFrequency.quarterly,
        ),
        local(2026, 4, 30),
      );
      expect(
        IssueCadence.nextDate(local(2024, 2, 29), PeriodicalFrequency.annual),
        local(2025, 2, 28),
      );
    });

    test('irregular has no next date', () {
      expect(
        IssueCadence.nextDate(local(2026, 1, 1), PeriodicalFrequency.irregular),
        isNull,
      );
    });
  });

  group('IssueCadence.next', () {
    test('no previous issue ⇒ nothing suggested', () {
      final p = IssueCadence.next(
        latest: null,
        frequency: PeriodicalFrequency.monthly,
      );
      expect(p.isEmpty, isTrue);
      expect(p, same(IssuePrefill.none));
    });

    test('a single issue: same volume, number + 1, date + one step', () {
      final p = IssueCadence.next(
        latest: IssueOf(
          periodicalUid: 'u',
          volume: 249,
          issueNumber: 10,
          issueDate: local(2026, 10, 1),
        ),
        frequency: PeriodicalFrequency.monthly,
      );
      expect(p.volume, 249);
      expect(p.issueNumber, 11);
      expect(p.issueDate, local(2026, 11, 1));
      expect(p.isEmpty, isFalse);
      expect(p.toString(), contains('no: 11'));
    });

    test('missing parts stay missing; unknown cadence gives no date', () {
      final p = IssueCadence.next(
        latest: IssueOf(periodicalUid: 'u', issueDate: local(2026, 10, 1)),
        frequency: null,
      );
      expect(p.volume, isNull);
      expect(p.issueNumber, isNull);
      expect(p.issueDate, isNull);
      final q = IssueCadence.next(
        latest: const IssueOf(periodicalUid: 'u', issueNumber: 3),
        frequency: PeriodicalFrequency.weekly,
      );
      expect(q.issueNumber, 4);
      expect(q.issueDate, isNull, reason: 'no previous date to step from');
    });

    test(
      'a bound volume: date steps from boundUntil, numbers not suggested',
      () {
        final p = IssueCadence.next(
          latest: IssueOf(
            periodicalUid: 'u',
            volume: 248,
            issueNumber: 1,
            issueDate: local(2025, 7, 1),
            boundUntil: local(2026, 6, 1),
          ),
          frequency: PeriodicalFrequency.monthly,
        );
        expect(p.volume, isNull);
        expect(p.issueNumber, isNull);
        expect(p.issueDate, local(2026, 7, 1));
      },
    );
  });
}
