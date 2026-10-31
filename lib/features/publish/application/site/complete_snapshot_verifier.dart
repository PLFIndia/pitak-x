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
  }) : this(
         reader: reader,
         sleep: sleep,
         attempts: ReadBackBudget.gitHubPagesAttempts,
         interval: ReadBackBudget.gitHubPagesInterval,
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

  /// Proves all [files] at [siteUrl] and all [deletedPaths] absent.
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
    for (var attempt = 0; attempt < attempts && pending.isNotEmpty; attempt++) {
      await _sleep(interval);
      for (final path in pending.keys.toList()) {
        final expected = pending[path]!;
        final outcome = await _read(
          siteUrl,
          path,
          expected.maxBytes,
          '$revision-$attempt',
        );
        if (expected.matches(outcome)) pending.remove(path);
      }
    }
    return pending.isEmpty;
  }

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
