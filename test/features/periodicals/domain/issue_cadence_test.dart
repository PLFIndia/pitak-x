import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/issue_cadence.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

// Next-issue prefill: numbers from the latest issue, dates one UTC calendar-
// day/month step later. Legacy local-midnight inputs normalize first.
void main() {
  int utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch;

  group('IssueCadence.nextDate', () {
    test('day-based cadences add canonical calendar days', () {
      expect(
        IssueCadence.nextDate(utc(2026, 1, 1), PeriodicalFrequency.weekly),
        utc(2026, 1, 8),
      );
      expect(
        IssueCadence.nextDate(utc(2026, 1, 1), PeriodicalFrequency.fortnightly),
        utc(2026, 1, 15),
      );
    });

    test('canonical days stay stable across spring-forward and fall-back', () {
      expect(
        IssueCadence.nextDate(utc(2026, 3, 1), PeriodicalFrequency.weekly),
        utc(2026, 3, 8),
      );
      expect(
        IssueCadence.nextDate(utc(2026, 10, 25), PeriodicalFrequency.weekly),
        utc(2026, 11, 1),
      );
      expect(
        IssueCadence.nextDate(
          utc(2026, 11, 1),
          PeriodicalFrequency.fortnightly,
        ),
        utc(2026, 11, 15),
      );
    });

    test('legacy local midnight cannot fall back to the previous day', () {
      final legacyFallBack = DateTime(2026, 11).millisecondsSinceEpoch;
      final legacySpringForward = DateTime(2026, 3, 8).millisecondsSinceEpoch;

      expect(
        IssueCadence.nextDate(legacyFallBack, PeriodicalFrequency.weekly),
        utc(2026, 11, 8),
      );
      expect(
        IssueCadence.nextDate(legacySpringForward, PeriodicalFrequency.weekly),
        utc(2026, 3, 15),
      );
    });

    test('month-based cadences step UTC calendar months with clamping', () {
      expect(
        IssueCadence.nextDate(utc(2026, 1, 31), PeriodicalFrequency.monthly),
        utc(2026, 2, 28),
      );
      expect(
        IssueCadence.nextDate(utc(2026, 1, 31), PeriodicalFrequency.bimonthly),
        utc(2026, 3, 31),
      );
      expect(
        IssueCadence.nextDate(utc(2026, 1, 31), PeriodicalFrequency.quarterly),
        utc(2026, 4, 30),
      );
      expect(
        IssueCadence.nextDate(utc(2024, 2, 29), PeriodicalFrequency.annual),
        utc(2025, 2, 28),
      );
    });

    test('irregular has no next date', () {
      expect(
        IssueCadence.nextDate(utc(2026, 1, 1), PeriodicalFrequency.irregular),
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
          issueDate: utc(2026, 10, 1),
        ),
        frequency: PeriodicalFrequency.monthly,
      );
      expect(p.volume, 249);
      expect(p.issueNumber, 11);
      expect(p.issueDate, utc(2026, 11, 1));
      expect(p.isEmpty, isFalse);
      expect(p.toString(), contains('no: 11'));
    });

    test('missing parts stay missing; unknown cadence gives no date', () {
      final p = IssueCadence.next(
        latest: IssueOf(periodicalUid: 'u', issueDate: utc(2026, 10, 1)),
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

    test('a bound volume steps from boundUntil, not its numbers', () {
      final p = IssueCadence.next(
        latest: IssueOf(
          periodicalUid: 'u',
          volume: 248,
          issueNumber: 1,
          issueDate: utc(2025, 7, 1),
          boundUntil: utc(2026, 6, 1),
        ),
        frequency: PeriodicalFrequency.monthly,
      );
      expect(p.volume, isNull);
      expect(p.issueNumber, isNull);
      expect(p.issueDate, utc(2026, 7, 1));
    });
  });
}
