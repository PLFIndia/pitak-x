/// Exact-origin read-back for every file in a complete snapshot.
library;

import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Publishes are verified as a set: one match never proves the whole site.
final class CompleteSnapshotVerifier {
  /// Creates a bounded grouped verifier.
  const CompleteSnapshotVerifier({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    this.attempts = ReadBackBudget.defaultAttempts,
    this.interval = ReadBackBudget.defaultInterval,
    this.clock,
  }) : _reader = reader,
       _sleep = sleep;

  /// A verifier that waits as long as GitHub says a Pages build may take.
  ///
  /// A commit is not public until GitHub Pages rebuilds the site, and GitHub
  /// documents that this "can take up to 10 minutes". The default 60 s budget
  /// was shorter than real builds: the S11 J.7 smoke (2026-10-29) measured 48 s
  /// and 81 s, so a move to GitHub could fail even though its commit was fine,
  /// and every retry commits again and restarts the build. The budget comes
  /// from [ReadBackBudget]. It still fails closed when the time runs out.
  const CompleteSnapshotVerifier.gitHubPages({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    int Function()? clock,
  }) : this(
         reader: reader,
         sleep: sleep,
         attempts: ReadBackBudget.gitHubPagesAttempts,
         interval: ReadBackBudget.gitHubPagesInterval,
         clock: clock,
       );

  /// Polling rounds for a GitHub Pages build (60 × 10 s = 10 minutes).
  static const int gitHubPagesAttempts = ReadBackBudget.gitHubPagesAttempts;

  /// Delay before each GitHub Pages polling round.
  static const Duration gitHubPagesInterval =
      ReadBackBudget.gitHubPagesInterval;

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;

  /// Maximum polling rounds shared by all expectations.
  final int attempts;

  /// Delay before each round.
  final Duration interval;

  /// Clock in epoch milliseconds, or null for the system clock.
  ///
  /// Injectable so a test can prove the overall deadline stops NEW reads
  /// without waiting ten real minutes (review finding 5).
  final int Function()? clock;

  /// At most this many reads run at once (the established four-worker bound).
  ///
  /// Why (beginner note): a move verification reads every pending file once
  /// per round. Serially, 1,000 covers can outlast the whole ten-minute
  /// budget, so the proof could never finish even on a healthy site. Four at
  /// a time keeps the read count identical while finishing four times sooner.
  static const int maxConcurrentReads = 4;

  /// Proves all [files] at [siteUrl] and all [deletedPaths] absent.
  ///
  /// The whole operation is bounded by one deadline (`attempts × interval`,
  /// measured from entry): no read starts after it, and already-started reads
  /// finish under the reader's own transport bound. A slow or huge site
  /// therefore fails closed instead of outliving the budget (review
  /// finding 5).
  Future<bool> verify({
    required String siteUrl,
    required List<PublishFile> files,
    required int revision,
    List<String> deletedPaths = const [],
  }) async {
    final pending = <String, _Expectation>{
      for (final file in files)
        file.path: _Expectation(file.gitSha, file.bytes.length),
      for (final path in deletedPaths) path: const _Expectation.absent(),
    };
    final budget = Duration(milliseconds: interval.inMilliseconds * attempts);
    final deadline = _now() + budget.inMilliseconds;

    for (var attempt = 0; attempt < attempts && pending.isNotEmpty; attempt++) {
      final remaining = deadline - _now();
      if (remaining <= 0) break; // no new read after the deadline
      final wait = remaining < interval.inMilliseconds
          ? Duration(milliseconds: remaining)
          : interval;
      await _sleep(wait);
      if (_now() >= deadline) break;

      // One read per pending path this round, at most four in flight. The
      // order is the pending map's order, so a slow path cannot reshuffle
      // which read belongs to which expectation.
      final paths = pending.keys.toList();
      for (var start = 0; start < paths.length; start += maxConcurrentReads) {
        if (_now() >= deadline) break; // in-flight reads still finish
        var end = start + maxConcurrentReads;
        if (end > paths.length) end = paths.length;
        final batch = paths.sublist(start, end);
        final outcomes = await Future.wait([
          for (final path in batch)
            _read(siteUrl, path, pending[path]!.maxBytes, '$revision-$attempt'),
        ]);
        for (var i = 0; i < batch.length; i++) {
          if (pending[batch[i]]!.matches(outcomes[i])) {
            pending.remove(batch[i]);
          }
        }
      }
    }
    return pending.isEmpty;
  }

  int _now() => clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  Future<PublishedSiteReadOutcome> _read(
    String siteUrl,
    String path,
    int maxBytes,
    String revision,
  ) async {
    try {
      return await _reader.readOutcome(
        siteUrl: siteUrl,
        path: path,
        maxBytes: maxBytes,
        cacheBuster: revision,
      );
    } on Exception {
      return const PublishedSiteReadUnreadable();
    }
  }
}

final class _Expectation {
  const _Expectation(this.sha, int size)
    : maxBytes = size == 0 ? 1 : size,
      absent = false;
  const _Expectation.absent() : sha = null, maxBytes = 1, absent = true;

  final String? sha;
  final int maxBytes;
  final bool absent;

  bool matches(PublishedSiteReadOutcome outcome) {
    if (absent) return outcome is PublishedSiteReadAbsent;
    return outcome is PublishedSiteReadBody &&
        GitBlobSha.of(outcome.bytes) == sha;
  }
}
