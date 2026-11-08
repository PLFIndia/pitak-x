import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';

/// PLAN.md §1 / §8 "Token recovery": the incarnation + epoch identity must
/// make leftovers from a previous settings lineage unmatchable.
void main() {
  const incA = '0f6c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
  const incB = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  group('WatchSettingsToken', () {
    test('sameAs compares the whole token, never the epoch alone', () {
      const a2 = WatchSettingsToken(incarnation: incA, epoch: 2);
      const b2 = WatchSettingsToken(incarnation: incB, epoch: 2);
      const a3 = WatchSettingsToken(incarnation: incA, epoch: 3);

      expect(
        a2.sameAs(const WatchSettingsToken(incarnation: incA, epoch: 2)),
        isTrue,
      );
      expect(a2.sameAs(b2), isFalse);
      expect(a2.sameAs(a3), isFalse);
      expect(a2.sameIncarnation(a3), isTrue);
      expect(a2.sameIncarnation(b2), isFalse);
    });

    test('reset scenario: old epoch 2 leftovers never match a new lineage '
        'that also reaches epoch 2', () {
      // Previous life: enabled, disabled → epoch 2 artifacts on disk.
      var old = EventsWatchSettings.initial(incA);
      old = old.withEnabled(enabled: true).withEnabled(enabled: false);
      expect(old.token.epoch, 2);
      final leftover = old.token;

      // Reset → fresh incarnation at epoch 0, then enable twice → epoch 2.
      var fresh = EventsWatchSettings.initial(incB);
      fresh = fresh.withEnabled(enabled: true).withEnabled(enabled: true);
      expect(fresh.token.epoch, 2);

      expect(fresh.token.sameAs(leftover), isFalse);
    });

    test('nextEpoch never reuses a value', () {
      var token = const WatchSettingsToken(incarnation: incA, epoch: 0);
      final seen = <int>{};
      for (var i = 0; i < 5; i++) {
        token = token.nextEpoch();
        expect(seen.add(token.epoch), isTrue);
      }
    });

    test(
      'validate accepts UUID-shaped incarnations and non-negative epochs',
      () {
        expect(
          WatchSettingsToken.validate(incarnation: incA, epoch: 0),
          isNotNull,
        );
        expect(
          WatchSettingsToken.validate(incarnation: incA, epoch: 99),
          isNotNull,
        );
      },
    );

    test('validate rejects hostile input', () {
      final bad = <(Object?, Object?)>[
        (null, 0),
        ('', 0),
        ('UPPER-CASE-NOT-ALLOWED', 0),
        ('../etc/passwd', 0),
        ('a' * 65, 0),
        (incA, -1),
        (incA, '1'),
        (incA, 1.5),
        (incA, null),
        (42, 0),
      ];
      for (final (inc, epoch) in bad) {
        expect(
          WatchSettingsToken.validate(incarnation: inc, epoch: epoch),
          isNull,
          reason: '$inc / $epoch',
        );
      }
    });

    test('toString never leaks the incarnation', () {
      const t = WatchSettingsToken(incarnation: incA, epoch: 1);
      expect(t.toString(), isNot(contains(incA)));
    });
  });

  group('EventsWatchSettings', () {
    test('initial is OFF at epoch 0 with no explanation acknowledged', () {
      final s = EventsWatchSettings.initial(incA);
      expect(s.enabled, isFalse);
      expect(s.token.epoch, 0);
      expect(s.needsExplanation, isTrue);
    });

    test(
      'every explicit enable/disable bumps the epoch, even if unchanged',
      () {
        final s = EventsWatchSettings.initial(incA);
        final on = s.withEnabled(enabled: true);
        final onAgain = on.withEnabled(enabled: true);
        expect(on.token.epoch, 1);
        expect(onAgain.token.epoch, 2);
        expect(onAgain.enabled, isTrue);
      },
    );

    test('acknowledging the explanation does NOT change the token', () {
      final s = EventsWatchSettings.initial(incA).withEnabled(enabled: true);
      final ack = s.withExplanationAcknowledged();
      expect(ack.token.sameAs(s.token), isTrue);
      expect(ack.needsExplanation, isFalse);
    });

    test('validate rejects wrong types and absurd versions', () {
      EventsWatchSettings? v(Object? e, Object? ack) =>
          EventsWatchSettings.validate(
            enabled: e,
            incarnation: incA,
            epoch: 0,
            acknowledgedExplanationVersion: ack,
          );
      expect(v(true, 0), isNotNull);
      expect(v('true', 0), isNull);
      expect(v(true, -1), isNull);
      expect(v(true, 1001), isNull);
      expect(v(true, '1'), isNull);
    });

    test(
      'pausedForNoLibraries: absent = false, bool kept, other = corrupt',
      () {
        EventsWatchSettings? v(Object? paused) => EventsWatchSettings.validate(
          enabled: true,
          incarnation: incA,
          epoch: 1,
          acknowledgedExplanationVersion: 1,
          pausedForNoLibraries: paused,
        );
        expect(v(null)!.pausedForNoLibraries, isFalse);
        expect(v(true)!.pausedForNoLibraries, isTrue);
        expect(v(false)!.pausedForNoLibraries, isFalse);
        expect(v('true'), isNull);
        expect(v(1), isNull);
      },
    );

    test('a pause keeps the token; any explicit enable/disable clears it '
        'with a new epoch; acknowledgement preserves it', () {
      final on = EventsWatchSettings.initial(incA).withEnabled(enabled: true);
      final paused = on.withPausedForNoLibraries(paused: true);
      expect(paused.pausedForNoLibraries, isTrue);
      expect(paused.token.sameAs(on.token), isTrue);
      expect(paused.sameAs(on), isFalse);

      expect(paused.withExplanationAcknowledged().pausedForNoLibraries, isTrue);

      final off = paused.withEnabled(enabled: false);
      expect(off.pausedForNoLibraries, isFalse);
      expect(off.token.epoch, on.token.epoch + 1);
      expect(paused.withEnabled(enabled: true).pausedForNoLibraries, isFalse);
      expect(paused.withPausedForNoLibraries(paused: false).sameAs(on), isTrue);
    });
  });
}
