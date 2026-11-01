import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_pacing.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// SPECIFICATION of the lane's timing rules (ADR 0019 Decision 8, plan
/// AV6/AV11/C.4).
///
/// Every test runs under `fakeAsync`: the policy's clock reads fake time, and
/// a real `Timer` built from `delayUntil` must fire exactly when the policy
/// said — the way the lane (plan S6) will use it. No test waits for real.
void main() {
  const minute = 60 * 1000;
  const second = 1000;
  // 2026-11-01T10:00:00Z, an arbitrary but realistic epoch.
  const t0 = 1793527200000;

  /// Runs [body] with a pacing policy whose clock is fake time from [t0].
  void paced(void Function(FakeAsync async, AvailabilityPacing pacing) body) {
    fakeAsync((async) {
      final pacing = AvailabilityPacing(
        clock: () => t0 + async.elapsed.inMilliseconds,
      );
      body(async, pacing);
    });
  }

  /// Starts a timer for [startAt] and returns the fake time it fired at.
  int fireTime(FakeAsync async, AvailabilityPacing pacing, int startAt) {
    int? firedAt;
    Timer(pacing.delayUntil(startAt), () {
      firedAt = t0 + async.elapsed.inMilliseconds;
    });
    async.flushTimers();
    return firedAt!;
  }

  test('the constants are the ADR 0019 values', () {
    expect(AvailabilityPacing.debounce, const Duration(seconds: 20));
    expect(AvailabilityPacing.gitHubSpacing, const Duration(minutes: 6));
    expect(AvailabilityPacing.gitHubWindow, const Duration(minutes: 60));
    expect(AvailabilityPacing.gitHubBudget, 10);
    expect(AvailabilityPacing.retryBackoff, const [
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
    ]);
  });

  group('debounce (both hosts)', () {
    for (final host in PublishHost.values) {
      test('${host.name}: starts 20 s after the last change', () {
        paced((async, pacing) {
          final start = pacing.automaticStartAt(
            AvailabilityPacingInput(host: host, lastChangeAt: t0),
          );
          expect(start, t0 + 20 * second);
          expect(fireTime(async, pacing, start), t0 + 20 * second);
        });
      });
    }

    test('five quick changes become one publish, 20 s after the last', () {
      paced((async, pacing) {
        Timer? timer;
        var publishes = 0;
        int? firedAt;
        void change() {
          final now = t0 + async.elapsed.inMilliseconds;
          final start = pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              lastChangeAt: now,
            ),
          );
          timer?.cancel();
          timer = Timer(pacing.delayUntil(start), () {
            publishes++;
            firedAt = t0 + async.elapsed.inMilliseconds;
          });
        }

        for (var i = 0; i < 5; i++) {
          change();
          async.elapse(const Duration(seconds: 5));
        }
        async.flushTimers();

        expect(publishes, 1);
        // Last change at t0 + 20 s, so the publish is at t0 + 40 s.
        expect(firedAt, t0 + 40 * second);
      });
    });

    test('a change long ago adds no wait; no change starts now', () {
      paced((async, pacing) {
        expect(
          pacing.automaticStartAt(
            const AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              lastChangeAt: t0 - 10 * minute,
            ),
          ),
          t0,
        );
        expect(
          pacing.automaticStartAt(
            const AvailabilityPacingInput(host: PublishHost.cloudflare),
          ),
          t0,
        );
      });
    });
  });

  group('GitHub spacing', () {
    test('waits 6 min after the last availability publish', () {
      paced((async, pacing) {
        final start = pacing.automaticStartAt(
          const AvailabilityPacingInput(
            host: PublishHost.github,
            lastChangeAt: t0,
            lastAvailabilityPublishAt: t0 - minute,
          ),
        );
        expect(start, t0 + 5 * minute);
        expect(fireTime(async, pacing, start), t0 + 5 * minute);
      });
    });

    test('does not apply to Cloudflare', () {
      paced((async, pacing) {
        expect(
          pacing.automaticStartAt(
            const AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              lastChangeAt: t0,
              lastAvailabilityPublishAt: t0 - minute,
            ),
          ),
          t0 + 20 * second,
        );
      });
    });

    test('a busy hour of changes never exceeds 10 commits in 60 min', () {
      // Plan G.4 row 8: a change every 4 minutes for two hours. With only
      // availability commits, spacing alone keeps the budget, and no change
      // waits longer than spacing + debounce.
      paced((async, pacing) {
        final commits = <int>[];
        var longestWait = 0;
        int? oldestUnpublishedChange;
        Timer? timer;

        int now() => t0 + async.elapsed.inMilliseconds;

        void change() {
          oldestUnpublishedChange ??= now();
          final start = pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.github,
              lastChangeAt: now(),
              lastAvailabilityPublishAt: commits.isEmpty ? null : commits.last,
              gitHubCommitTimes: commits,
            ),
          );
          timer?.cancel();
          timer = Timer(pacing.delayUntil(start), () {
            commits.add(now());
            final waited = now() - oldestUnpublishedChange!;
            if (waited > longestWait) longestWait = waited;
            oldestUnpublishedChange = null;
          });
        }

        for (var i = 0; i < 30; i++) {
          change();
          async.elapse(const Duration(minutes: 4));
        }
        async.flushTimers();

        for (final commit in commits) {
          final inWindow = commits
              .where((c) => c > commit - 60 * minute && c <= commit)
              .length;
          expect(inWindow, lessThanOrEqualTo(10));
        }
        expect(
          longestWait,
          lessThanOrEqualTo(6 * minute + 20 * second),
          reason: 'the guide promises "up to about 7 minutes"',
        );
      });
    });
  });

  group('GitHub rolling budget (all sections counted)', () {
    test('ten commits in the last hour wait for the oldest to leave', () {
      paced((async, pacing) {
        // Ten commits, one every 5 minutes, the oldest 50 minutes ago.
        final times = [for (var i = 0; i < 10; i++) t0 - (50 - 5 * i) * minute];
        final start = pacing.automaticStartAt(
          AvailabilityPacingInput(
            host: PublishHost.github,
            gitHubCommitTimes: times,
          ),
        );
        // The oldest (t0 - 50 min) leaves the window at t0 + 10 min.
        expect(start, t0 + 10 * minute);
        expect(fireTime(async, pacing, start), t0 + 10 * minute);
      });
    });

    test('nine commits leave room for one more now', () {
      paced((async, pacing) {
        final times = [for (var i = 0; i < 9; i++) t0 - i * minute];
        expect(
          pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.github,
              gitHubCommitTimes: times,
            ),
          ),
          t0,
        );
      });
    });

    test('a commit exactly one window old no longer counts', () {
      paced((async, pacing) {
        final times = [
          t0 - 60 * minute,
          for (var i = 0; i < 9; i++) t0 - i * minute,
        ];
        expect(
          pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.github,
              gitHubCommitTimes: times,
            ),
          ),
          t0,
        );
      });
    });

    test('a future time (clock went back) waits at most one window', () {
      paced((async, pacing) {
        final times = [for (var i = 0; i < 10; i++) t0 + 24 * 60 * minute];
        expect(
          pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.github,
              gitHubCommitTimes: times,
            ),
          ),
          t0 + 60 * minute,
        );
      });
    });

    test('Cloudflare ignores the GitHub budget', () {
      paced((async, pacing) {
        final times = [for (var i = 0; i < 10; i++) t0 - i * minute];
        expect(
          pacing.automaticStartAt(
            AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              gitHubCommitTimes: times,
            ),
          ),
          t0,
        );
      });
    });
  });

  group('retry backoff (AV11)', () {
    test('1, 2, 5, 10 min, then every 10 min', () {
      expect(AvailabilityPacing.retryDelay(1), const Duration(minutes: 1));
      expect(AvailabilityPacing.retryDelay(2), const Duration(minutes: 2));
      expect(AvailabilityPacing.retryDelay(3), const Duration(minutes: 5));
      expect(AvailabilityPacing.retryDelay(4), const Duration(minutes: 10));
      expect(AvailabilityPacing.retryDelay(5), const Duration(minutes: 10));
      expect(AvailabilityPacing.retryDelay(99), const Duration(minutes: 10));
      expect(AvailabilityPacing.retryDelay(0), const Duration(minutes: 1));
    });

    test('a retry waits for its backoff after the failure', () {
      paced((async, pacing) {
        final start = pacing.retryStartAt(
          const AvailabilityPacingInput(
            host: PublishHost.cloudflare,
            consecutiveFailures: 3,
            lastFailureAt: t0,
          ),
        )!;
        expect(start, t0 + 5 * minute);
        expect(fireTime(async, pacing, start), t0 + 5 * minute);
      });
    });

    test('a retry never breaks the GitHub spacing', () {
      paced((async, pacing) {
        expect(
          pacing.retryStartAt(
            const AvailabilityPacingInput(
              host: PublishHost.github,
              lastAvailabilityPublishAt: t0,
              consecutiveFailures: 1,
              lastFailureAt: t0,
            ),
          ),
          t0 + 6 * minute,
        );
      });
    });

    test('no recorded failure means no retry is scheduled', () {
      paced((async, pacing) {
        expect(
          pacing.retryStartAt(
            const AvailabilityPacingInput(host: PublishHost.cloudflare),
          ),
          isNull,
        );
        expect(
          pacing.retryStartAt(
            const AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              consecutiveFailures: 2,
            ),
          ),
          isNull,
        );
      });
    });

    test('repeated failures never loop: each retry is later than the last', () {
      paced((async, pacing) {
        final attempts = <int>[];
        var failures = 0;
        int? lastFailureAt = t0;

        for (var i = 0; i < 6; i++) {
          failures++;
          final start = pacing.retryStartAt(
            AvailabilityPacingInput(
              host: PublishHost.cloudflare,
              consecutiveFailures: failures,
              lastFailureAt: lastFailureAt,
            ),
          )!;
          final firedAt = fireTime(async, pacing, start);
          attempts.add(firedAt);
          lastFailureAt = firedAt; // The attempt fails again at once.
        }

        final gaps = [
          for (var i = 0; i < attempts.length; i++)
            attempts[i] - (i == 0 ? t0 : attempts[i - 1]),
        ];
        expect(gaps, [
          1 * minute,
          2 * minute,
          5 * minute,
          10 * minute,
          10 * minute,
          10 * minute,
        ]);
      });
    });
  });

  group('Update availability now', () {
    test('starts at once, skipping debounce and spacing', () {
      paced((async, pacing) {
        final manual = pacing.manualStart(
          const AvailabilityPacingInput(
            host: PublishHost.github,
            lastChangeAt: t0,
            lastAvailabilityPublishAt: t0 - minute,
          ),
        );
        expect(manual.startAt, t0);
        expect(manual.gitHubBudgetUsedUp, isFalse);
      });
    });

    test('says when GitHub may delay it because the budget is used up', () {
      paced((async, pacing) {
        final times = [for (var i = 0; i < 10; i++) t0 - i * minute];
        final manual = pacing.manualStart(
          AvailabilityPacingInput(
            host: PublishHost.github,
            gitHubCommitTimes: times,
          ),
        );
        expect(manual.startAt, t0, reason: 'a deliberate tap still goes now');
        expect(manual.gitHubBudgetUsedUp, isTrue);
      });
    });

    test('Cloudflare never reports a GitHub budget', () {
      paced((async, pacing) {
        final times = [for (var i = 0; i < 10; i++) t0 - i * minute];
        expect(
          pacing
              .manualStart(
                AvailabilityPacingInput(
                  host: PublishHost.cloudflare,
                  gitHubCommitTimes: times,
                ),
              )
              .gitHubBudgetUsedUp,
          isFalse,
        );
      });
    });
  });

  test('delayUntil is never negative', () {
    paced((async, pacing) {
      expect(pacing.delayUntil(t0 - minute), Duration.zero);
      expect(pacing.delayUntil(t0 + second), const Duration(seconds: 1));
    });
  });
}
