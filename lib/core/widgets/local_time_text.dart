/// One way to show "when" for an epoch-millisecond time (core presentation
/// helper).
///
/// Used wherever the app prints a recent moment next to a status, such as the
/// availability status row (publish) and the viewer's "updated 2:05 pm"
/// summary (network). A time from today shows only the time; an earlier day
/// also shows its short date ("2 Nov, 2:05 pm"). Both parts come from
/// `MaterialLocalizations`, so they follow the device's language and 12/24-
/// hour setting.
library;

import 'package:flutter/material.dart';

/// [millis] as a locale-aware local time, with the short date in front when
/// it is not on the same local day as [nowMillis].
String formatLocalMoment(
  BuildContext context,
  int millis, {
  required int nowMillis,
}) {
  final localizations = MaterialLocalizations.of(context);
  final at = DateTime.fromMillisecondsSinceEpoch(millis);
  final today = DateTime.fromMillisecondsSinceEpoch(nowMillis);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at));
  final sameDay =
      at.year == today.year && at.month == today.month && at.day == today.day;
  return sameDay ? time : '${localizations.formatShortMonthDay(at)}, $time';
}
