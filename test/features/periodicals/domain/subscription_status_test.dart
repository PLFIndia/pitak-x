import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';

// ADR 0013 D5: derived from (end date, now); 30-day "expiring soon" window
// (maintainer decision 2026-10-21). Boundaries pinned to the millisecond.
void main() {
  final now = DateTime.utc(2026, 10, 21, 12);
  Periodical ending(DateTime end) =>
      Periodical(title: 'A', subscriptionEnd: end.millisecondsSinceEpoch);

  group('SubscriptionStatus.of', () {
    test('no end date ⇒ untracked (a start alone does not track)', () {
      expect(
        SubscriptionStatus.of(const Periodical(title: 'A'), now),
        SubscriptionStatus.untracked,
      );
      expect(
        SubscriptionStatus.of(
          Periodical(title: 'A', subscriptionStart: now.millisecondsSinceEpoch),
          now,
        ),
        SubscriptionStatus.untracked,
      );
    });

    test('end before now ⇒ lapsed; end == now ⇒ expiring soon', () {
      expect(
        SubscriptionStatus.of(
          ending(now.subtract(const Duration(milliseconds: 1))),
          now,
        ),
        SubscriptionStatus.lapsed,
      );
      expect(
        SubscriptionStatus.of(ending(now), now),
        SubscriptionStatus.expiringSoon,
      );
    });

    test('the 30/31-day boundary', () {
      expect(
        SubscriptionStatus.of(ending(now.add(const Duration(days: 30))), now),
        SubscriptionStatus.expiringSoon,
      );
      expect(
        SubscriptionStatus.of(
          ending(now.add(const Duration(days: 30, milliseconds: 1))),
          now,
        ),
        SubscriptionStatus.active,
      );
      expect(
        SubscriptionStatus.of(ending(now.add(const Duration(days: 31))), now),
        SubscriptionStatus.active,
      );
      expect(
        SubscriptionStatus.of(ending(now.add(const Duration(days: 1))), now),
        SubscriptionStatus.expiringSoon,
      );
    });

    test('a window that has not started yet is simply active', () {
      final p = Periodical(
        title: 'A',
        subscriptionStart: now
            .add(const Duration(days: 10))
            .millisecondsSinceEpoch,
        subscriptionEnd: now
            .add(const Duration(days: 400))
            .millisecondsSinceEpoch,
      );
      expect(SubscriptionStatus.of(p, now), SubscriptionStatus.active);
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
