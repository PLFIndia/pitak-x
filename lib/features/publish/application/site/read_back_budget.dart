/// The ONE place a published-site read-back wait is chosen (publish
/// application layer; fix-plan L17).
///
/// Why one budget object (beginner note): a commit or deploy is not public
/// until the host has rebuilt the site. Cloudflare serves a deployment almost
/// immediately, but a GitHub Pages build genuinely takes minutes and GitHub
/// documents "up to 10 minutes". Before this file, the move destination waited
/// 10 minutes while the GitHub SOURCE retirement still gave up after 60 s, so
/// the same build could be judged differently by the two halves of one move.
///
/// The numbers here are the single source of truth: the verifiers take their
/// defaults from them, and a test pins the total wait.
library;

/// Named read-back waits for the two publish hosts.
abstract final class ReadBackBudget {
  /// Rounds for a host that serves a change within seconds (Cloudflare).
  static const int defaultAttempts = 12;

  /// Delay before each default round. 12 × 5 s = 60 s.
  static const Duration defaultInterval = Duration(seconds: 5);

  /// Polling rounds for a GitHub Pages build: 60 × 10 s = the documented
  /// "up to 10 minutes".
  static const int gitHubPagesAttempts = 60;

  /// Delay before each GitHub Pages polling round.
  static const Duration gitHubPagesInterval = Duration(seconds: 10);

  /// Progress copy for a wait that can legitimately last minutes.
  static const String gitHubPagesWaitNote = 'This can take a few minutes.';

  /// Total wall-clock budget of [gitHubPagesAttempts] × [gitHubPagesInterval].
  static Duration get gitHubPagesTotal =>
      gitHubPagesInterval * gitHubPagesAttempts;

  /// Total wall-clock budget of [defaultAttempts] × [defaultInterval].
  static Duration get defaultTotal => defaultInterval * defaultAttempts;
}
