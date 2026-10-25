/// A Gregorian calendar day, stored at the persistence/wire boundary as epoch
/// milliseconds at 00:00 UTC (library domain, pure Dart; ADR 0013/0014).
///
/// A calendar day is NOT an instant. "2026-01-15" means the same magazine
/// cover date in Kolkata and New York, while an instant names one physical
/// moment whose local date depends on the device timezone. Issue and
/// subscription fields use this type's rules; `addedDate`, `removedAt`, loan
/// dates, and `exportedAt` remain instants and must not be converted.
library;

import 'package:pitaka/features/library/domain/catalogue_rules.dart';

/// An immutable, validated year/month/day value.
final class CalendarDate implements Comparable<CalendarDate> {
  /// Creates a valid Gregorian calendar day.
  factory CalendarDate(int year, int month, int day) {
    if (year < 1) {
      throw ArgumentError.value(year, 'year', 'Must be positive');
    }
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'Must be 1..12');
    }
    final lastDay = _daysInMonth(year, month);
    if (day < 1 || day > lastDay) {
      throw ArgumentError.value(day, 'day', 'Must be 1..$lastDay');
    }
    return CalendarDate._(
      year,
      month,
      day,
      DateTime.utc(year, month, day).millisecondsSinceEpoch,
    );
  }

  const CalendarDate._(this.year, this.month, this.day, this.epochMillis);

  /// Takes calendar fields from a Flutter local date-picker value.
  ///
  /// The picker's hour and zone are deliberately irrelevant: the user chose a
  /// day, not a moment. Use [toPickerDate] for the reverse conversion.
  factory CalendarDate.fromPickerDate(DateTime picked) =>
      CalendarDate(picked.year, picked.month, picked.day);

  /// Reads the UTC calendar fields of a stored value without legacy conversion.
  ///
  /// New writes are canonical already. Display and arithmetic use this method
  /// so they never reinterpret a canonical UTC day through the device zone.
  factory CalendarDate.fromEpochMillis(int epochMillis) {
    _checkStoredMillis(epochMillis);
    final utc = DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);
    return CalendarDate(utc.year, utc.month, utc.day);
  }

  /// Converts a legacy stored value to its calendar day, exactly once.
  ///
  /// Exact 00:00 UTC is already canonical and is returned unchanged. Any
  /// other value is interpreted in the CURRENT device timezone, and that
  /// local year/month/day is kept. This is idempotent and preserves dates
  /// created on this device by older builds. If an artifact was created in a
  /// different timezone, its original zone cannot be recovered; the ADR
  /// records that honest limitation.
  factory CalendarDate.fromStoredMillis(int epochMillis) {
    _checkStoredMillis(epochMillis);
    final utc = DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: true);
    if (_isUtcMidnight(utc)) return CalendarDate.fromEpochMillis(epochMillis);
    return CalendarDate.fromPickerDate(
      DateTime.fromMillisecondsSinceEpoch(epochMillis),
    );
  }

  /// The positive Gregorian year, within Dart's representable DateTime range.
  final int year;

  /// The month number (1..12).
  final int month;

  /// The day of the month (1..31, limited by the month).
  final int day;

  /// Canonical persistence/wire representation: this day at 00:00 UTC.
  final int epochMillis;

  /// A nullable, fail-soft display conversion.
  ///
  /// Null, the catalogue's `0` unset sentinel, and unrepresentable values
  /// produce null. Other values are read through UTC fields, never the local
  /// zone. Migration uses [normalizeStoredMillis] instead, so a non-null zero
  /// in a date column remains intact there.
  static CalendarDate? fromEpochMillisOrNull(int? epochMillis) {
    if (epochMillis == null ||
        epochMillis == 0 ||
        !CatalogueRules.isValidDateMillis(epochMillis)) {
      return null;
    }
    return CalendarDate.fromEpochMillis(epochMillis);
  }

  /// Normalizes one legacy stored integer to canonical UTC midnight.
  static int normalizeStoredMillis(int epochMillis) =>
      CalendarDate.fromStoredMillis(epochMillis).epochMillis;

  /// Nullable variant of [normalizeStoredMillis]; null stays null.
  static int? normalizeOptionalStoredMillis(int? epochMillis) =>
      epochMillis == null ? null : normalizeStoredMillis(epochMillis);

  /// The local picker value for this day, with no time-of-day information.
  DateTime toPickerDate() => DateTime(year, month, day);

  /// Moves by calendar days using UTC fields, never local 24-hour durations.
  CalendarDate addDays(int days) {
    final result = DateTime.utc(year, month, day + days);
    return CalendarDate(result.year, result.month, result.day);
  }

  /// Moves by calendar months, clamping to the target month's final day.
  CalendarDate addMonthsClamped(int months) {
    final firstOfTarget = DateTime.utc(year, month + months);
    final lastDay = _daysInMonth(firstOfTarget.year, firstOfTarget.month);
    return CalendarDate(
      firstOfTarget.year,
      firstOfTarget.month,
      day > lastDay ? lastDay : day,
    );
  }

  static int _daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) {
      return 29;
    }
    return lengths[month - 1];
  }

  static void _checkStoredMillis(int epochMillis) {
    if (!CatalogueRules.isValidDateMillis(epochMillis)) {
      throw ArgumentError.value(
        epochMillis,
        'epochMillis',
        'Not a representable catalogue date',
      );
    }
  }

  static bool _isUtcMidnight(DateTime value) =>
      value.hour == 0 &&
      value.minute == 0 &&
      value.second == 0 &&
      value.millisecond == 0 &&
      value.microsecond == 0;

  @override
  int compareTo(CalendarDate other) => epochMillis.compareTo(other.epochMillis);

  /// Value comparison using the domain's dependency-free convention.
  bool sameAs(CalendarDate other) =>
      other.year == year && other.month == month && other.day == day;

  @override
  String toString() {
    final yyyy = year.toString().padLeft(4, '0');
    final mm = month.toString().padLeft(2, '0');
    final dd = day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}
