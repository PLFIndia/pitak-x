/// Origin-bound verification of an ordinary Cloudflare publication (R16).
///
/// What is checked is the DOCUMENTED read-back set (ADR 0017 S8): the marker,
/// `books.json`, the root `index.html`, `library.json` or its real 404, the
/// events files when recorded, at most two posters, and the exact
/// removed-poster 404s — plus, since ADR 0019 (Decision 11),
/// `availability.json` when recorded or its exact 404 after a removal. An
/// availability-only deploy reads a narrower scope: the fresh marker and that
/// one file ([CloudflareReadBackScope.availabilityOnly]).
/// Covers are deliberately not read back: the upload protocol already
/// guaranteed every hash before the completion token, and a version is atomic
/// (fix-plan M2).
///
/// Three outcomes replace the old verified/not-verified pair, because "the
/// site answered with different bytes" and "the site could not be reached" need
/// different next steps.
///
/// Speed (plan SP2): the first round reads at once, and the reads of one round
/// run side by side, at most
/// [CloudflarePublicationVerifier.defaultMaxConcurrentReads] at a time. The
/// budget, the three outcomes and the "last observation per path decides" rule
/// are the same as when every read waited for the previous one.
library;

import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// WHICH files a read-back must see.
///
/// Why two scopes (beginner note): a Worker version is atomic and its marker
/// carries an id that is new for every deploy (ADR 0017 Decision 6). So once
/// the fresh marker is served, the whole version is the one just deployed,
/// and only the files the deploy CHANGED still need reading. An ordinary
/// publish changes the catalogue or events, so it reads the documented set;
/// the availability lane changes one file, so it reads the marker and that
/// file (ADR 0019 Decision 11, plan AV13).
enum CloudflareReadBackScope {
  /// The documented set of an ordinary or combined deploy (ADR 0017 S8, plus
  /// `availability.json` when recorded or removed).
  ordinary,

  /// An availability-only deploy: the fresh marker plus `availability.json`,
  /// or its exact 404 after a removal.
  availabilityOnly,
}

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
  ///
  /// [maxConcurrentReads] defaults to [defaultMaxConcurrentReads]; a value
  /// below 1 counts as 1. Production never passes it: the tests pass 1 to
  /// compare the side-by-side reads with one-at-a-time reads.
  const CloudflarePublicationVerifier({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    int Function()? clock,
    int maxConcurrentReads = defaultMaxConcurrentReads,
  }) : _reader = reader,
       _sleep = sleep,
       _clock = clock,
       _maxConcurrentReads = maxConcurrentReads < 1 ? 1 : maxConcurrentReads;

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;
  final int Function()? _clock;
  final int _maxConcurrentReads;

  /// The most reads one round keeps in flight at once (plan SP2).
  ///
  /// Why four (beginner note): the ordinary set is up to about ten small
  /// files. Four at a time finishes a round in two or three network round
  /// trips instead of ten, without a phone opening a burst of connections
  /// to one site. The saved-library refresh uses the same number for the
  /// same reason (`RefreshNetworkUseCase.defaultConcurrency`).
  static const int defaultMaxConcurrentReads = 4;

  int _now() => (_clock ?? _systemClock)();

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  /// Verifies [manifest] at [target]. [markerBytes] is available immediately
  /// after assembly; retry-verification instead uses the recorded marker sha.
  ///
  /// [budget] decides how long the check may take: a deployment made moments
  /// ago may wait for a fresh edge, an earlier record may not.
  ///
  /// [scope] decides which files are read. Only a deployment made moments ago
  /// by the availability lane may narrow it; every earlier record is checked
  /// against the ordinary set, which is the superset.
  Future<CloudflarePublicationVerification> verify({
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest manifest,
    required int revision,
    List<int> markerBytes = const [],
    List<String> deletedPaths = const [],
    CloudflareReadBackScope scope = CloudflareReadBackScope.ordinary,
    CloudflareReadBackBudget budget = CloudflareReadBackBudget.afterDeploy,
    void Function(int rounds)? onRounds,
  }) async {
    final pending = _expectations(
      manifest: manifest,
      markerBytes: markerBytes,
      deletedPaths: deletedPaths,
      scope: scope,
    );
    if (pending == null) {
      // No documented core means nothing can be proven, not that something
      // contradicted the record.
      return CloudflarePublicationVerification.unreachable;
    }

    final deadline = budget.deadline.inMilliseconds;
    final started = _now();
    bool pastDeadline() => _now() - started >= deadline;
    // The LAST observation per path decides contradicted vs unreachable.
    final wrongContent = <String>{};
    var attempt = 0;
    while (pending.isNotEmpty && attempt < budget.rounds) {
      if (pastDeadline()) break;
      // SP2: round one reads at once (a deploy that is already served is
      // proven without any wait); every later round waits [interval] first.
      if (attempt > 0) await _sleep(budget.interval);
      attempt++;
      final paths = pending.keys.toList()..sort();
      final verdicts = await _readRound(
        siteUrl: target.siteUrl,
        paths: paths,
        expectations: pending,
        cacheBuster: '$revision-$attempt',
        pastDeadline: pastDeadline,
      );
      // Applied in path order after the round. Each path is read at most once
      // per round, so the order cannot change the result; a path the deadline
      // left unread this round keeps its previous observation.
      for (final path in paths) {
        final verdict = verdicts[path];
        if (verdict == null) continue;
        switch (verdict) {
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
    // Plan S0: hand the round count to the debug-only publish timings. A null
    // callback (release builds) makes this a no-op.
    onRounds?.call(attempt);
    if (pending.isEmpty) return CloudflarePublicationVerification.verified;
    return wrongContent.isEmpty
        ? CloudflarePublicationVerification.unreachable
        : CloudflarePublicationVerification.contradicted;
  }

  /// The read-back set for [scope], or null when the record is not usable.
  static Map<String, _Expectation>? _expectations({
    required CloudflareSiteManifest manifest,
    required List<int> markerBytes,
    required List<String> deletedPaths,
    required CloudflareReadBackScope scope,
  }) {
    final markerEntry = manifest.entryFor(CloudflareLimits.markerPath);
    if (markerEntry == null) return null;
    final marker = _Expectation.content(markerEntry, exactBytes: markerBytes);
    final availability = _availabilityExpectation(manifest, deletedPaths);
    switch (scope) {
      case CloudflareReadBackScope.availabilityOnly:
        // ADR 0019 Decision 11: the fresh marker pins the whole atomic
        // version, so the one file this deploy changed completes the proof.
        // A deploy that neither wrote nor removed the file has nothing this
        // scope could prove, so it proves nothing (never "verified").
        if (availability == null) return null;
        return {
          CloudflareLimits.markerPath: marker,
          AvailabilityDocument.path: availability,
        };
      case CloudflareReadBackScope.ordinary:
        return _ordinaryExpectations(
          manifest: manifest,
          marker: marker,
          availability: availability,
          deletedPaths: deletedPaths,
        );
    }
  }

  /// ADR 0019 Decision 11: `availability.json` is expected with its recorded
  /// bytes when the deploy carries it, or as an exact 404 when this deploy
  /// removed it; null when the site never had it (nothing to read).
  static _Expectation? _availabilityExpectation(
    CloudflareSiteManifest manifest,
    List<String> deletedPaths,
  ) {
    final entry = manifest.entryFor(AvailabilityDocument.path);
    if (entry != null) return _Expectation.content(entry);
    if (deletedPaths.contains(AvailabilityDocument.path)) {
      return const _Expectation.absent();
    }
    return null;
  }

  /// The documented ADR 0017 S8 set, or null without the catalogue core.
  static Map<String, _Expectation>? _ordinaryExpectations({
    required CloudflareSiteManifest manifest,
    required _Expectation marker,
    required _Expectation? availability,
    required List<String> deletedPaths,
  }) {
    final booksEntry = manifest.entryFor('books.json');
    final indexEntry = manifest.entryFor('index.html');
    if (booksEntry == null || indexEntry == null) return null;
    final pending = <String, _Expectation>{
      CloudflareLimits.markerPath: marker,
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

    // ADR 0019 Decision 11: `availability.json` joins the set when recorded
    // or removed. The file is tiny, so it costs one small read.
    if (availability != null) pending[AvailabilityDocument.path] = availability;
    return pending;
  }

  /// Reads [paths] once each with at most [_maxConcurrentReads] in flight, and
  /// returns the verdict of every path that was read.
  ///
  /// The worker-pool pattern of the saved-library refresh (`refresh_run.dart`):
  /// a few workers take the next path from one shared queue. Dart runs on one
  /// thread, and there is no `await` between the queue check and the take, so
  /// no two workers can take the same path. Reads therefore START in path
  /// order, exactly as they did one by one. No read starts once
  /// [pastDeadline] is true; a read already in flight finishes, bounded by its
  /// own transport limit (as the budget documents).
  Future<Map<String, _Verdict>> _readRound({
    required String siteUrl,
    required List<String> paths,
    required Map<String, _Expectation> expectations,
    required String cacheBuster,
    required bool Function() pastDeadline,
  }) async {
    final queue = [...paths];
    final verdicts = <String, _Verdict>{};
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (pastDeadline()) return;
        final path = queue.removeAt(0);
        final expectation = expectations[path]!;
        final outcome = await _read(
          siteUrl: siteUrl,
          path: path,
          maxBytes: expectation.maxBytes,
          cacheBuster: cacheBuster,
        );
        verdicts[path] = expectation.classify(outcome);
      }
    }

    final workers = queue.length < _maxConcurrentReads
        ? queue.length
        : _maxConcurrentReads;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return verdicts;
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
