/// When the availability lane may publish (publish domain, pure Dart;
/// ADR 0019 Decision 8, plan AV6/AV11/C.4).
///
/// Why pacing exists (beginner note): lending five books at the counter should
/// become ONE publish, not five, and GitHub Pages has a soft limit of about
/// 10 site builds per hour. So the lane waits:
///  - **debounce** — 20 s after the last loan change, on both hosts;
///  - **GitHub spacing** — at least 6 min between availability publishes;
///  - **GitHub budget** — at most 10 commits from this app in any rolling
///    60 min, counting every section (catalogue and events publishes too).
///
/// After a failure the lane retries on a bounded **backoff**: 1, 2, 5 and
/// 10 min, then every 10 min while the app runs. Never an immediate loop
/// (ADR 0019 Decision 8, plan G6).
///
/// **Update availability now** is a deliberate tap: it skips the debounce and
/// the GitHub spacing and starts at once. It still COUNTS towards the rolling
/// budget (the caller records its commit like any other), and when the budget
/// is already used up the status says "GitHub may delay this update".
///
/// The policy is pure: it decides times, it does not wait. The clock is
/// injected (epoch milliseconds, like every other publish clock), so tests
/// drive it with `fake_async`, and the lane (plan S6) turns a start time into
/// a timer with [AvailabilityPacing.delayUntil].
library;

import 'dart:math' as math;

import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// What the lane knows when it asks "when may I publish?". All times are
/// epoch milliseconds.
final class AvailabilityPacingInput {
  /// Creates the input. Every time is optional: a missing one simply adds no
  /// wait.
  const AvailabilityPacingInput({
    required this.host,
    this.lastChangeAt,
    this.lastAvailabilityPublishAt,
    this.gitHubCommitTimes = const [],
    this.consecutiveFailures = 0,
    this.lastFailureAt,
  });

  /// The active host. Spacing and budget apply to GitHub only.
  final PublishHost host;

  /// When the newest unpublished loan change happened (debounce anchor).
  final int? lastChangeAt;

  /// When the last availability publish to GitHub was accepted (spacing
  /// anchor).
  final int? lastAvailabilityPublishAt;

  /// When this app's recent GitHub commits were accepted, every section
  /// counted (budget input; the lane store keeps the newest
  /// [AvailabilityPacing.gitHubBudget]).
  final List<int> gitHubCommitTimes;

  /// Failed attempts in a row since the last success (0 = none).
  final int consecutiveFailures;

  /// When the last failed attempt ended (backoff anchor).
  final int? lastFailureAt;
}

/// The answer for **Update availability now**.
final class AvailabilityManualStart {
  /// Creates the answer.
  const AvailabilityManualStart({
    required this.startAt,
    required this.gitHubBudgetUsedUp,
  });

  /// When to start: always now.
  final int startAt;

  /// True when GitHub's rolling budget is already used up, so the status can
  /// say "GitHub may delay this update". Always false on Cloudflare.
  final bool gitHubBudgetUsedUp;
}

/// The lane's timing rules.
final class AvailabilityPacing {
  /// Creates the policy over [clock] (epoch milliseconds).
  const AvailabilityPacing({required int Function() clock}) : _clock = clock;

  final int Function() _clock;

  /// Wait after the last loan change, on both hosts.
  static const Duration debounce = Duration(seconds: 20);

  /// Minimum time between two availability publishes on GitHub.
  ///
  /// The guide's "up to about 7 minutes" copy is this plus about a minute of
  /// Pages build (plan AV16); S8 pins the copy to this constant by a test.
  static const Duration gitHubSpacing = Duration(minutes: 6);

  /// The rolling window of the GitHub budget.
  static const Duration gitHubWindow = Duration(minutes: 60);

  /// Most GitHub commits from this app in any [gitHubWindow].
  static const int gitHubBudget = 10;

  /// Waits after the 1st, 2nd, 3rd and 4th failure in a row; every later
  /// failure waits the last value again.
  static const List<Duration> retryBackoff = [
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// The backoff wait after [consecutiveFailures] failures in a row
  /// (values below 1 are treated as 1).
  static Duration retryDelay(int consecutiveFailures) {
    final index = math.min(
      math.max(consecutiveFailures, 1),
      retryBackoff.length,
    );
    return retryBackoff[index - 1];
  }

  /// When an automatic publish may start after a change, at app start, or on
  /// resume: never before now, the debounce, and — on GitHub — the spacing
  /// and the rolling budget.
  int automaticStartAt(AvailabilityPacingInput input) {
    final now = _clock();
    var start = now;
    final changedAt = input.lastChangeAt;
    if (changedAt != null) {
      start = math.max(start, _past(changedAt, now) + debounce.inMilliseconds);
    }
    if (input.host == PublishHost.github) {
      final publishedAt = input.lastAvailabilityPublishAt;
      if (publishedAt != null) {
        start = math.max(
          start,
          _past(publishedAt, now) + gitHubSpacing.inMilliseconds,
        );
      }
      start = math.max(start, _budgetFreeAt(input.gitHubCommitTimes, now));
    }
    return start;
  }

  /// When the backoff retry may start, or null when no failure is recorded.
  ///
  /// The backoff is one more wait on top of [automaticStartAt], so a retry can
  /// never break the debounce, the spacing or the budget either.
  int? retryStartAt(AvailabilityPacingInput input) {
    final failedAt = input.lastFailureAt;
    if (input.consecutiveFailures < 1 || failedAt == null) return null;
    final now = _clock();
    final backoffEnds =
        _past(failedAt, now) +
        retryDelay(input.consecutiveFailures).inMilliseconds;
    return math.max(automaticStartAt(input), backoffEnds);
  }

  /// The answer for **Update availability now**: start at once, and say
  /// whether GitHub's budget is already used up.
  AvailabilityManualStart manualStart(AvailabilityPacingInput input) {
    final now = _clock();
    final usedUp =
        input.host == PublishHost.github &&
        _budgetFreeAt(input.gitHubCommitTimes, now) > now;
    return AvailabilityManualStart(startAt: now, gitHubBudgetUsedUp: usedUp);
  }

  /// How long to wait from now until [startAt] (never negative).
  Duration delayUntil(int startAt) =>
      Duration(milliseconds: math.max(0, startAt - _clock()));

  /// The earliest time at which fewer than [gitHubBudget] of [times] fall in
  /// the rolling window `(t - gitHubWindow, t]`.
  ///
  /// A commit leaves the window exactly [gitHubWindow] after it happened. So
  /// with the commits newest first, the budget frees up when the
  /// [gitHubBudget]-th newest commit is one window old.
  int _budgetFreeAt(List<int> times, int now) {
    if (times.length < gitHubBudget) return now;
    final newestFirst = [for (final time in times) _past(time, now)]
      ..sort((a, b) => b.compareTo(a));
    return math.max(
      now,
      newestFirst[gitHubBudget - 1] + gitHubWindow.inMilliseconds,
    );
  }

  /// [time], but never later than [now].
  ///
  /// A stored time in the future means the phone's clock went backwards.
  /// Reading it as "now" keeps every wait bounded by its own length (at most
  /// one window), instead of blocking the lane until the clock catches up.
  static int _past(int time, int now) => math.min(time, now);
}
