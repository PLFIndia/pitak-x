/// Unambiguous user-visible date formatting (pure Dart, no locale service).
library;

const _months = <String>[
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats [date] as `20 November 2026` using its existing zone fields.
String formatDisplayDateTime(DateTime date) {
  return '${date.day} ${_months[date.month]} ${date.year}';
}

/// Formats an epoch-millis instant as `20 November 2026`.
///
/// Set [utc] for canonical UTC calendar-day fields (magazine issues and
/// subscriptions). Leave it false for local instants such as loans/addedDate.
String formatDisplayDate(int epochMillis, {bool utc = false}) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMillis, isUtc: utc);
  return formatDisplayDateTime(date);
}

/// Nullable boundary-safe form of [formatDisplayDate] for untrusted stored
/// data. Values outside Dart's epoch range are rejected without throwing.
String? formatDisplayDateOrNull(int? epochMillis, {bool utc = false}) {
  if (epochMillis == null) return null;
  const maxDateMillis = 8640000000000000;
  if (epochMillis > maxDateMillis || epochMillis < -maxDateMillis) return null;
  return formatDisplayDate(epochMillis, utc: utc);
}

/// Formats a local instant as `20 November 2026, 14:05`.
String formatDisplayDateTimeWithTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatDisplayDateTime(date)}, $hour:$minute';
}
