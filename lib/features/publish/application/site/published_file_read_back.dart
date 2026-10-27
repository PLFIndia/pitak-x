/// Bounded read-back of one published file (application layer; Cloudflare plan
/// R16).
///
/// Why a shared helper (beginner note): both publishes ("catalogue" and
/// "events") must answer the same question after committing — "does the LIVE
/// site serve exactly the bytes I just pushed?" — and both must answer it
/// WITHOUT waiting forever. One implementation keeps the budget, the
/// cache-buster and the origin binding identical for both, so a fix to the
/// polling rule cannot land for one section only.
///
/// The comparison is byte-for-byte against the bytes that were committed,
/// capped at exactly their length: a longer body cannot be the file we wrote,
/// so it is not proof of anything.
library;

import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Polls a published file until the live site serves the expected bytes.
final class PublishedFileReadBack {
  /// Creates the read-back over a bounded verifier.
  const PublishedFileReadBack({
    required PublishedSiteVerifier verifier,
    required Future<void> Function(Duration) sleep,
    this.attempts = defaultAttempts,
    this.interval = defaultInterval,
  }) : _verifier = verifier,
       _sleep = sleep;

  /// How many polls one read-back may make (Orange budgets 120 s; 60 s covers
  /// typical Pages builds and keeps the worst case tolerable on a phone).
  static const int defaultAttempts = 12;

  /// Pause between polls.
  static const Duration defaultInterval = Duration(seconds: 5);

  final PublishedSiteVerifier _verifier;
  final Future<void> Function(Duration) _sleep;

  /// Maximum number of polls.
  final int attempts;

  /// Pause between polls.
  final Duration interval;

  /// Returns true once `<siteUrl><path>` serves exactly [expected].
  ///
  /// Null means "not provable within the budget" (still building, unreachable,
  /// refused) — never a silent success. [revision] seeds a fresh cache-buster
  /// per poll so a CDN cannot keep answering with a stale copy.
  Future<bool?> untilServed({
    required String siteUrl,
    required String path,
    required List<int> expected,
    required int revision,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await _sleep(interval);
      // Origin-bound, redirect-free, capped at exactly the expected size.
      final body = await _verifier.read(
        siteUrl: siteUrl,
        path: path,
        maxBytes: expected.isEmpty ? 1 : expected.length,
        cacheBuster: '$revision-$attempt',
      );
      if (body != null && _sameBytes(body, expected)) return true;
    }
    return null;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
