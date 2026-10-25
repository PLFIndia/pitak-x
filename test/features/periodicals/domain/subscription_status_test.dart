import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';

// ADR 0013 D5: derived from calendar days; the end date remains active for
// the whole local day and the expiring window is 30 calendar days.
void main() {
  Periodical ending(int year, int month, int day) => Periodical(
    title: 'A',
    subscriptionEnd: DateTime.utc(year, month, day).millisecondsSinceEpoch,
  );

  group('SubscriptionStatus.of', () {
    test('no end date ⇒ untracked (a start alone does not track)', () {
      final now = DateTime(2026, 10, 21, 12);
      expect(
        SubscriptionStatus.of(const Periodical(title: 'A'), now),
        SubscriptionStatus.untracked,
      );
      expect(
        SubscriptionStatus.of(
          Periodical(
            title: 'A',
            subscriptionStart: DateTime.utc(
              2026,
              10,
              21,
            ).millisecondsSinceEpoch,
          ),
          now,
        ),
        SubscriptionStatus.untracked,
      );
    });

    test('midnight/noon/23:59 on the end date ⇒ expiringSoon', () {
      final end = ending(2026, 10, 21);
      for (final current in [
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 21, 12),
        DateTime(2026, 10, 21, 23, 59, 59, 999),
      ]) {
        expect(
          SubscriptionStatus.of(end, current),
          SubscriptionStatus.expiringSoon,
          reason: '$current is still on the selected end date',
        );
      }
    });

    test('the day before is not lapsed; the following day is', () {
      final end = ending(2026, 10, 21);
      expect(
        SubscriptionStatus.of(end, DateTime(2026, 10, 20, 23, 59, 59, 999)),
        SubscriptionStatus.expiringSoon,
      );
      for (final current in [
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 22, 12),
      ]) {
        expect(
          SubscriptionStatus.of(end, current),
          SubscriptionStatus.lapsed,
          reason: 'the end date is yesterday at $current',
        );
      }
    });

    test('the exact 30/31 local-calendar-day boundary', () {
      final current = DateTime(2026, 3, 1, 12);
      expect(
        SubscriptionStatus.of(ending(2026, 3, 31), current),
        SubscriptionStatus.expiringSoon,
      );
      expect(
        SubscriptionStatus.of(ending(2026, 4, 1), current),
        SubscriptionStatus.active,
      );
      expect(
        SubscriptionStatus.of(ending(2026, 3, 2), current),
        SubscriptionStatus.expiringSoon,
      );
    });

    test('a window that has not started yet is simply active', () {
      final periodical = Periodical(
        title: 'A',
        subscriptionStart: DateTime.utc(2026, 3, 11).millisecondsSinceEpoch,
        subscriptionEnd: DateTime.utc(2027, 3).millisecondsSinceEpoch,
      );
      expect(
        SubscriptionStatus.of(periodical, DateTime(2026, 3, 1, 12)),
        SubscriptionStatus.active,
      );
    });

    test('badge labels: none for untracked, words for the rest', () {
      expect(SubscriptionStatus.untracked.badgeLabel, isNull);
      expect(SubscriptionStatus.active.badgeLabel, 'Subscribed');
      expect(SubscriptionStatus.expiringSoon.badgeLabel, 'Expiring soon');
      expect(SubscriptionStatus.lapsed.badgeLabel, 'Lapsed');
    });

    test('the window constant is 30 days', () {
      expect(SubscriptionStatus.expiringSoonWindow, const Duration(days: 30));
    });
  });
}
