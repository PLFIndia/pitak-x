/// The projected title of a magazine issue (periodicals domain, pure Dart;
/// ADR 0013 D3).
///
/// Every issue row carries a plain `title` so the Library list, search,
/// publish, backup and merge keep working unchanged. That title is COMPOSED
/// here from the series name and the issue's numbers/dates — never typed —
/// and rewritten whenever the series is renamed (`IssueProjection`). Month
/// names are a fixed English list so two devices compose the same string
/// for the same issue (locale-dependent formatting would break merge
/// identity and search expectations).
library;

import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';

/// Composes issue titles.
abstract final class IssueTitle {
  /// Three-letter English month names, index 1..12 (index 0 unused).
  static const List<String> months = [
    '',
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
  ];

  /// The separator between the series name and the issue part.
  static const String separator = ' — ';

  /// The title for [issue] of the series called [seriesTitle].
  ///
  /// Shapes (null parts are simply omitted):
  /// - single issue: `Chandamama — Vol 249 No 10 (Oct 2026)`,
  ///   `Chandamama — No 10`, `Chandamama — Oct 2026`;
  /// - bound volume: `Chandamama — Vol 248, Jul 2025 – Jun 2026`;
  /// - nothing to add: `Chandamama`.
  static String compose(String seriesTitle, IssueOf issue) {
    final series = seriesTitle.trim();
    final numbers = _numbers(issue);
    final String dates;
    if (issue.isBound) {
      final from = _monthYear(issue.issueDate);
      final until = _monthYear(issue.boundUntil);
      dates = [from, until].whereType<String>().join(' – ');
    } else {
      dates = _monthYear(issue.issueDate) ?? '';
    }
    final String part;
    if (numbers.isEmpty && dates.isEmpty) {
      part = '';
    } else if (numbers.isEmpty) {
      part = dates;
    } else if (dates.isEmpty) {
      part = numbers;
    } else if (issue.isBound) {
      part = '$numbers, $dates';
    } else {
      part = '$numbers ($dates)';
    }
    return part.isEmpty ? series : '$series$separator$part';
  }

  /// `Vol 249 No 10`, `Vol 249`, `No 10` or `''`.
  static String _numbers(IssueOf issue) => [
    if (issue.volume != null) 'Vol ${issue.volume}',
    if (issue.issueNumber != null) 'No ${issue.issueNumber}',
  ].join(' ');

  /// `Oct 2026` for a canonical epoch-millis calendar day, or null.
  static String? _monthYear(int? millis) {
    if (millis == null) return null;
    final date = CalendarDate.fromEpochMillis(millis);
    return '${months[date.month]} ${date.year}';
  }

  /// The UTC calendar year of an epoch-millis day — the projected
  /// `publishedYear`. It never depends on the device timezone.
  static int? yearOf(int? millis) =>
      millis == null ? null : CalendarDate.fromEpochMillis(millis).year;
}
