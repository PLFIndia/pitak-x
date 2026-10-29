/// Origin-bound verification of an ordinary Cloudflare publication (R16).
///
/// What is checked is the DOCUMENTED read-back set (ADR 0017 S8): the marker,
/// `books.json`, the root `index.html`, `library.json` or its real 404, the
/// events files when recorded, at most two posters, and the exact
/// removed-poster 404s. Covers are deliberately not read back: the upload
/// protocol already guaranteed every hash before the completion token, and a
/// version is atomic (fix-plan M2).
///
/// Three outcomes replace the old verified/not-verified pair, because "the
/// site answered with different bytes" and "the site could not be reached" need
/// different next steps.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Required read-back outcome for a deployment or deploy-free retry.
enum CloudflarePublicationVerification {
  /// Every required origin-bound check passed.
  verified,

  /// The site answered, but at least one required file has different bytes
  /// (or serves a body where a 404 was required). Polling cannot fix that: a
  /// whole-site replacement is the only honest next step.
  contradicted,

  /// Nothing contradicted the record; the site could not be checked within the
  /// budget (timeout, 404 where content was expected, oversize, redirect).
  /// The manifest keeps its state; this never authorizes a deployment.
  unreachable,
}

/// Verifies a complete ordinary Worker snapshot using public, unauthenticated
/// reads at the exact target origin.
final class CloudflarePublicationVerifier {
  /// Creates the verifier over the shared structured public-read port.
  ///
  /// [clock] returns epoch milliseconds and defaults to the system clock; the
  /// deadline tests inject a fake one.
  const CloudflarePublicationVerifier({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    int Function()? clock,
  }) : _reader = reader,
       _sleep = sleep,
       _clock = clock;

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;
  final int Function()? _clock;

  int _now() => (_clock ?? _systemClock)();

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  /// Verifies [manifest] at [target]. [markerBytes] is available immediately
  /// after assembly; retry-verification instead uses the recorded marker sha.
  ///
  /// [budget] decides how long the check may take: a deployment made moments
  /// ago may wait for a fresh edge, an earlier record may not.
  Future<CloudflarePublicationVerification> verify({
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest manifest,
    required int revision,
    List<int> markerBytes = const [],
    List<String> deletedPaths = const [],
    CloudflareReadBackBudget budget = CloudflareReadBackBudget.afterDeploy,
  }) async {
    final pending = _expectations(
      manifest: manifest,
      markerBytes: markerBytes,
      deletedPaths: deletedPaths,
    );
    if (pending == null) {
      // No documented core means nothing can be proven, not that something
      // contradicted the record.
      return CloudflarePublicationVerification.unreachable;
    }

    final deadline = budget.deadline.inMilliseconds;
    final started = _now();
    // The LAST observation per path decides contradicted vs unreachable.
    final wrongContent = <String>{};
    var attempt = 0;
    while (pending.isNotEmpty && attempt < budget.rounds) {
      if (_now() - started >= deadline) break;
      attempt++;
      await _sleep(budget.interval);
      final paths = pending.keys.toList()..sort();
      for (final path in paths) {
        if (_now() - started >= deadline) break;
        final expectation = pending[path]!;
        final outcome = await _read(
          siteUrl: target.siteUrl,
          path: path,
          maxBytes: expectation.maxBytes,
          cacheBuster: '$revision-$attempt',
        );
        switch (expectation.classify(outcome)) {
          case _Verdict.matched:
            pending.remove(path);
            wrongContent.remove(path);
          case _Verdict.wrongContent:
            wrongContent.add(path);
          case _Verdict.unreachable:
            wrongContent.remove(path);
        }
      }
    }
    if (pending.isEmpty) return CloudflarePublicationVerification.verified;
    return wrongContent.isEmpty
        ? CloudflarePublicationVerification.unreachable
        : CloudflarePublicationVerification.contradicted;
  }

  /// The documented read-back set, or null when the record is not usable.
  Map<String, _Expectation>? _expectations({
    required CloudflareSiteManifest manifest,
    required List<int> markerBytes,
    required List<String> deletedPaths,
  }) {
    final markerEntry = manifest.entryFor(CloudflareLimits.markerPath);
    final booksEntry = manifest.entryFor('books.json');
    final indexEntry = manifest.entryFor('index.html');
    if (markerEntry == null || booksEntry == null || indexEntry == null) {
      return null;
    }
    final pending = <String, _Expectation>{
      CloudflareLimits.markerPath: _Expectation.content(
        markerEntry,
        exactBytes: markerBytes,
      ),
      'books.json': _Expectation.content(booksEntry),
      'index.html': _Expectation.content(indexEntry),
    };

    final descriptor = manifest.entryFor('library.json');
    pending['library.json'] = descriptor == null
        ? const _Expectation.absent()
        : _Expectation.content(descriptor);

    for (final path in const ['events.json', 'events.html']) {
      final entry = manifest.entryFor(path);
      if (entry != null) pending[path] = _Expectation.content(entry);
    }

    // At most two posters: enough to prove poster bytes without turning the
    // check into a whole-site download (the old verifier's real cost).
    final posters = manifest.files.keys.where(
      (path) => path.startsWith('posters/'),
    );
    final sortedPosters = posters.toList()..sort();
    for (final path in sortedPosters.take(2)) {
      pending[path] = _Expectation.content(manifest.files[path]);
    }

    for (final path in deletedPaths) {
      if (path.startsWith('posters/') && !pending.containsKey(path)) {
        pending[path] = const _Expectation.absent();
      }
    }
    return pending;
  }

  Future<PublishedSiteReadOutcome> _read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    required String cacheBuster,
  }) async {
    // HTML assets answer their file name with a 307 (auto-trailing-slash),
    // and read-back follows no redirect, so ask the canonical address:
    // `index.html` is read at the root, `events.html` at `events`.
    final served = CloudflareHtmlRouting.servedPath(path);
    if (served == null) return const PublishedSiteReadUnreadable();
    try {
      return await _reader.readOutcome(
        siteUrl: siteUrl,
        path: served,
        maxBytes: maxBytes,
        cacheBuster: cacheBuster,
      );
    } on Exception {
      // Public verification failures are expected and deliberately detail-free.
      return const PublishedSiteReadUnreadable();
    }
  }
}

enum _Verdict { matched, wrongContent, unreachable }

final class _Expectation {
  const _Expectation.content(this.entry, {this.exactBytes = const []})
    : expectAbsent = false;

  const _Expectation.absent()
    : entry = null,
      exactBytes = const [],
      expectAbsent = true;

  final CloudflareAssetEntry? entry;
  final List<int> exactBytes;
  final bool expectAbsent;

  int get maxBytes {
    if (expectAbsent) return 1;
    if (exactBytes.isNotEmpty) return exactBytes.length;
    final size = entry!.size;
    return size == 0 ? 1 : size;
  }

  _Verdict classify(PublishedSiteReadOutcome outcome) {
    if (expectAbsent) {
      if (outcome is PublishedSiteReadAbsent) return _Verdict.matched;
      // A body where the record says "removed" is a real contradiction.
      if (outcome is PublishedSiteReadBody) return _Verdict.wrongContent;
      return _Verdict.unreachable;
    }
    if (outcome is PublishedSiteReadBody) {
      final body = outcome.bytes;
      final matches = exactBytes.isNotEmpty
          ? _sameBytes(body, exactBytes)
          : GitBlobSha.of(body) == entry!.sha;
      return matches ? _Verdict.matched : _Verdict.wrongContent;
    }
    // Absent or unreadable content may still be propagating: never a
    // contradiction.
    return _Verdict.unreachable;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
