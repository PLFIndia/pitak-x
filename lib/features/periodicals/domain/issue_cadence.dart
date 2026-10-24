/// Prefill for the "add issue" form from the latest issue and the
/// periodical's frequency (periodicals domain, pure Dart).
///
/// Why this exists (beginner note): a monthly magazine's next issue is almost
/// always "same volume, number + 1, one month later". Deriving that once,
/// here, means the form opens already filled in and the user corrects the
/// exception instead of typing the rule. Everything is a SUGGESTION — the
/// form shows it as editable values; nothing is persisted from here.
library;

import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
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

  /// Suggested cover calendar day at 00:00 UTC (latest day plus one cadence
  /// step), or null when the cadence is unknown/irregular or undated.
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
  /// Calendar arithmetic uses UTC year/month/day fields. Canonical values
  /// stay fixed; a legacy local-midnight input is normalized by the one
  /// shared rule first. Thus weekly steps remain on the same calendar day
  /// across DST, and month-based steps clamp without a timezone conversion.
  static int? nextDate(int from, PeriodicalFrequency frequency) {
    final start = CalendarDate.fromStoredMillis(from);
    final days = frequency.days;
    if (days != null) return start.addDays(days).epochMillis;
    final months = frequency.months;
    if (months == null) return null;
    return start.addMonthsClamped(months).epochMillis;
  }
}
