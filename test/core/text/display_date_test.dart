import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/text/display_date.dart';

void main() {
  test('formats full English month without a leading zero', () {
    final local = DateTime(2026, 11, 20);
    expect(formatDisplayDate(local.millisecondsSinceEpoch), '20 November 2026');
    expect(
      formatDisplayDate(DateTime(2026, 1, 3).millisecondsSinceEpoch),
      '3 January 2026',
    );
  });

  test('UTC calendar-day fields do not shift through the local zone', () {
    final utcMidnight = DateTime.utc(2026, 11, 20).millisecondsSinceEpoch;
    expect(formatDisplayDate(utcMidnight, utc: true), '20 November 2026');
  });

  test('nullable boundary rejects unset and out-of-range values', () {
    expect(formatDisplayDateOrNull(null), isNull);
    expect(formatDisplayDateOrNull(8640000000000001), isNull);
  });

  test('date and time use the same unambiguous day', () {
    final local = DateTime(2026, 11, 20, 14, 5);
    expect(formatDisplayDateTimeWithTime(local), '20 November 2026, 14:05');
  });
}
