/// Prefill for the "add issue" form from the latest issue and the
/// periodical's frequency (periodicals domain, pure Dart).
///
/// Why this exists (beginner note): a monthly magazine's next issue is almost
/// always "same volume, number + 1, one month later". Deriving that once,
/// here, means the form opens already filled in and the user corrects the
/// exception instead of typing the rule. Everything is a SUGGESTION — the
/// form shows it as editable values; nothing is persisted from here.
library;

import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// Suggested values for the next issue of a periodical.
final class IssuePrefill {
  /// Creates a prefill; every part is optional.
  const IssuePrefill({this.volume, this.issueNumber, this.issueDate});

  /// Nothing to suggest (no previous issue).
  static const IssuePrefill none = IssuePrefill();

  /// Suggested volume (the latest issue's volume, unchanged).
  final int? volume;

  /// Suggested issue number (the latest issue's number plus one).
  final int? issueNumber;

  /// Suggested cover date, epoch millis (latest date plus one cadence
  /// step), or null when the cadence is unknown/irregular or the latest
  /// issue has no date.
  final int? issueDate;

  /// True when at least one part is suggested.
  bool get isEmpty =>
      volume == null && issueNumber == null && issueDate == null;

  @override
  String toString() =>
      'IssuePrefill(vol: $volume, no: $issueNumber, date: $issueDate)';
}

/// Next-issue suggestions from the previous issue and the cadence.
abstract final class IssueCadence {
  /// Suggests the next issue after [latest] for a periodical with
  /// [frequency]. A bound volume's range ends at `boundUntil`, so the next
  /// date steps from THAT; its numbers are kept out of the suggestion
  /// (a bound volume rarely carries a meaningful issue number).
  static IssuePrefill next({
    required IssueOf? latest,
    required PeriodicalFrequency? frequency,
  }) {
    if (latest == null) return IssuePrefill.none;
    final from = latest.boundUntil ?? latest.issueDate;
    final date = (from == null || frequency == null)
        ? null
        : nextDate(from, frequency);
    if (latest.isBound) return IssuePrefill(issueDate: date);
    final number = latest.issueNumber;
    return IssuePrefill(
      volume: latest.volume,
      issueNumber: number == null ? null : number + 1,
      issueDate: date,
    );
  }

  /// [from] (epoch millis) plus one [frequency] step, or null for an
  /// irregular cadence.
  ///
  /// Calendar arithmetic is done in LOCAL time because the date picker stores
  /// a cover date as the instant of local midnight: "31 January + 1 month" is
  /// 28/29 February at local midnight, not a UTC instant that lands on the
  /// wrong local day. Day-based steps are exact multiples of 24 h.
  static int? nextDate(int from, PeriodicalFrequency frequency) {
    final days = frequency.days;
    if (days != null) {
      return from + Duration(days: days).inMilliseconds;
    }
    final months = frequency.months;
    if (months == null) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(from);
    return addMonthsClamped(start, months).millisecondsSinceEpoch;
  }

  /// [date] moved forward [months] calendar months, keeping the day of
  /// month but clamping it to the target month's length (31 Jan + 1 → 28 or
  /// 29 Feb). Time of day is preserved.
  static DateTime addMonthsClamped(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDay = _daysInMonth(year, month);
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      year,
      month,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  /// Number of days in [month] of [year] (Gregorian, leap years included).
  static int _daysInMonth(int year, int month) {
    // Day 0 of the NEXT month is the last day of this one.
    final next = month == 12 ? DateTime(year + 1) : DateTime(year, month + 1);
    return next.subtract(const Duration(days: 1)).day;
  }
}
