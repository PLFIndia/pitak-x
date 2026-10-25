import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';

void main() {
  group('CalendarDate validation and canonical storage', () {
    test('stores a valid day at 00:00 UTC', () {
      final date = CalendarDate(2026, 1, 15);

      expect(date.year, 2026);
      expect(date.month, 1);
      expect(date.day, 15);
      expect(
        date.epochMillis,
        DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
      );
      expect(date.toString(), '2026-01-15');
    });

    test('rejects invalid year, month, and day boundaries', () {
      expect(() => CalendarDate(0, 1, 1), throwsArgumentError);
      expect(CalendarDate(10000, 1, 1).year, 10000);
      expect(() => CalendarDate(2026, 0, 1), throwsArgumentError);
      expect(() => CalendarDate(2026, 13, 1), throwsArgumentError);
      expect(() => CalendarDate(2026, 1, 0), throwsArgumentError);
      expect(() => CalendarDate(2026, 2, 29), throwsArgumentError);
      expect(() => CalendarDate(2026, 4, 31), throwsArgumentError);
      expect(CalendarDate(2028, 2, 29).day, 29);
    });

    test('a local picker value contributes fields, not its instant', () {
      final picked = DateTime(2026, 1, 15, 23, 59, 58, 123);
      final date = CalendarDate.fromPickerDate(picked);

      expect(
        date.epochMillis,
        DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
      );
      expect(date.toPickerDate(), DateTime(2026, 1, 15));
    });

    test('legacy local midnight normalizes once and is idempotent', () {
      final legacy = DateTime(2026, 1, 15).millisecondsSinceEpoch;
      final canonical = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch;

      expect(CalendarDate.normalizeStoredMillis(legacy), canonical);
      expect(CalendarDate.normalizeStoredMillis(canonical), canonical);
      final legacyNoon = DateTime(2026, 1, 15, 12).millisecondsSinceEpoch;
      expect(CalendarDate.normalizeStoredMillis(legacyNoon), canonical);
    });

    test('null stays null and invalid stored values are rejected', () {
      expect(CalendarDate.normalizeOptionalStoredMillis(null), isNull);
      expect(() => CalendarDate.normalizeStoredMillis(-1), throwsArgumentError);
    });
  });

  group('CalendarDate arithmetic and ordering', () {
    test('day addition crosses months and years by calendar day', () {
      expect(
        CalendarDate(2026, 12, 31).addDays(1).sameAs(CalendarDate(2027, 1, 1)),
        isTrue,
      );
      expect(
        CalendarDate(2026, 10, 25).addDays(7).sameAs(CalendarDate(2026, 11, 1)),
        isTrue,
      );
      expect(
        CalendarDate(
          2026,
          11,
          1,
        ).addDays(14).sameAs(CalendarDate(2026, 11, 15)),
        isTrue,
      );
    });

    test('month addition clamps to the target month end', () {
      expect(
        CalendarDate(
          2026,
          1,
          31,
        ).addMonthsClamped(1).sameAs(CalendarDate(2026, 2, 28)),
        isTrue,
      );
      expect(
        CalendarDate(
          2028,
          1,
          31,
        ).addMonthsClamped(1).sameAs(CalendarDate(2028, 2, 29)),
        isTrue,
      );
      expect(
        CalendarDate(
          2026,
          11,
          30,
        ).addMonthsClamped(3).sameAs(CalendarDate(2027, 2, 28)),
        isTrue,
      );
      expect(
        CalendarDate(
          2026,
          3,
          31,
        ).addMonthsClamped(-1).sameAs(CalendarDate(2026, 2, 28)),
        isTrue,
      );
    });

    test('comparison uses calendar order', () {
      final earlier = CalendarDate(2026, 1, 15);
      final later = CalendarDate(2026, 1, 16);

      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
      expect(earlier.compareTo(CalendarDate(2026, 1, 15)), 0);
      expect(earlier.sameAs(CalendarDate(2026, 1, 15)), isTrue);
    });
  });
}
