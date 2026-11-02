/// How Pitak stays polite to GitHub's content-creation limit (pure domain;
/// plan J8, ADR 0020 Decision 6 amendment).
///
/// Why this exists (beginner note): every file a GitHub publish sends is one
/// "create a blob" request, and GitHub limits how many content-creating
/// requests one account may make: about 80 a minute and 500 an hour
/// (GitHub REST docs, "secondary rate limits"). A first publish of a large
/// library needs more than that. GitHub then answers 403 or 429, and its docs
/// say: do not retry before the `retry-after` header says so; if that header
/// is missing, wait at least a minute, and wait longer each time it keeps
/// failing. Continuing to send while refused "may result in the banning of
/// your integration" — and Pitak is ONE integration shared by every library,
/// so one phone ignoring the rule could hurt them all.
///
/// Two answers live here, as numbers and one rule:
///  - **pacing** (product decision J8 (b)): at most one blob request per
///    `blobSpacing`, so a publish stays under the per-minute limit by
///    construction;
///  - **the pause** after a refusal (`pauseAfterRefusal`): the server's hint
///    when it gives one, otherwise a doubling wait, always within
///    `minimumPause`..`maximumPause`.
library;

/// GitHub's content-creation limit, as Pitak applies it.
abstract final class GitHubContentLimit {
  /// The shortest time between the starts of two blob requests: at most 60 a
  /// minute, under GitHub's documented 80 (the tree, commit and ref move of
  /// the same commit add three more). Product decision J8 (b).
  static const Duration blobSpacing = Duration(seconds: 1);

  /// The shortest pause after a refusal: GitHub's documented minimum when
  /// the answer carries no `retry-after`.
  static const Duration minimumPause = Duration(minutes: 1);

  /// The longest pause Pitak keeps: the window of the hourly limit itself.
  ///
  /// A longer server hint is cut to this. Response headers cross a network
  /// Pitak does not control (AGENTS.md §6.5), and a hostile `retry-after` of
  /// a year must not switch publishing off for a year.
  static const Duration maximumPause = Duration(hours: 1);

  /// How long Pitak waits before sending to GitHub again after the
  /// [consecutiveRefusals]-th refusal in a row (1 for the first).
  ///
  /// [serverHint] is what GitHub asked for (`retry-after`, or the time until
  /// `x-ratelimit-reset` when no requests remain); null when it said nothing.
  /// The answer is the larger of that hint and a doubling backoff (1, 2, 4,
  /// 8 … minutes), kept within [minimumPause]..[maximumPause].
  static Duration pauseAfterRefusal({
    required Duration? serverHint,
    required int consecutiveRefusals,
  }) {
    // 1 → 1 min, 2 → 2 min, 3 → 4 min … The exponent is capped so the
    // multiplication can never overflow, whatever count a damaged store holds.
    final doublings = (consecutiveRefusals < 1 ? 1 : consecutiveRefusals) - 1;
    final backoff = minimumPause * (1 << (doublings > 6 ? 6 : doublings));
    final hint = serverHint ?? Duration.zero;
    final wanted = hint > backoff ? hint : backoff;
    if (wanted < minimumPause) return minimumPause;
    if (wanted > maximumPause) return maximumPause;
    return wanted;
  }
}
