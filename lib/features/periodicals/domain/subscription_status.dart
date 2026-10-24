/// Derived subscription state of a periodical (periodicals domain, pure
/// Dart; ADR 0013 D5).
///
/// Why derived and never stored (beginner note): a stored status would have
/// to be recomputed by some job every day and would drift the moment that
/// job did not run. A pure function of (end date, now) cannot drift, needs
/// no notification plumbing, and is trivially testable at its boundaries.
library;

import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// Where a periodical's subscription stands at a given moment.
enum SubscriptionStatus {
  /// No end date recorded: the subscription is not tracked.
  untracked,

  /// The end date is more than [SubscriptionStatus.expiringSoonWindow] away.
  active,

  /// The end date is today or within [SubscriptionStatus.expiringSoonWindow].
  expiringSoon,

  /// The end date has passed.
  lapsed;

  /// How long before the end date a subscription counts as "expiring soon"
  /// (maintainer decision 2026-10-21: 30 days).
  static const Duration expiringSoonWindow = Duration(days: 30);

  /// The status of [periodical] at [now].
  ///
  /// Boundaries use the current LOCAL calendar day and the subscription's
  /// canonical calendar days. The entire end date is [expiringSoon]; it is
  /// [lapsed] only when that day is yesterday or earlier. Exactly 30 calendar
  /// days away is still [expiringSoon]. A tracked subscription whose START is
  /// in the future is simply [active] — there is no "not started yet" state.
  static SubscriptionStatus of(Periodical periodical, DateTime now) {
    final end = periodical.subscriptionEnd;
    if (end == null) return SubscriptionStatus.untracked;
    final endDate = CalendarDate.fromEpochMillis(end);
    final today = CalendarDate.fromPickerDate(now);
    if (endDate.compareTo(today) < 0) return SubscriptionStatus.lapsed;
    final lastExpiringDay = today.addDays(expiringSoonWindow.inDays);
    if (endDate.compareTo(lastExpiringDay) <= 0) {
      return SubscriptionStatus.expiringSoon;
    }
    return SubscriptionStatus.active;
  }

  /// Short user-facing badge text; null for [untracked] (no badge).
  String? get badgeLabel => switch (this) {
    SubscriptionStatus.untracked => null,
    SubscriptionStatus.active => 'Subscribed',
    SubscriptionStatus.expiringSoon => 'Expiring soon',
    SubscriptionStatus.lapsed => 'Lapsed',
  };
}
