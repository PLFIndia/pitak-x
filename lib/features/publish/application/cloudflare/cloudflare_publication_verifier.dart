/// Origin-bound verification of an ordinary Cloudflare publication (R16).
///
/// One grouped polling budget covers the marker, catalogue, descriptor (or its
/// real 404), events JSON, current posters, and exact removed-poster 404s. A
/// fresh marker alone never proves the complete Worker snapshot is live.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Required read-back outcome for a deployment or deploy-free retry.
enum CloudflarePublicationVerification {
  /// Every required origin-bound check passed.
  verified,

  /// The bounded budget ended without complete proof. The manifest remains
  /// `deployed`; this never authorizes another deployment by itself.
  notVerified,
}

/// Verifies a complete ordinary Worker snapshot using public, unauthenticated
/// reads at the exact target origin.
final class CloudflarePublicationVerifier {
  /// Creates the verifier over the shared structured public-read port.
  const CloudflarePublicationVerifier({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    this.attempts = 12,
    this.interval = const Duration(seconds: 5),
  }) : _reader = reader,
       _sleep = sleep;

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;

  /// Maximum grouped polling rounds.
  final int attempts;

  /// Delay before each polling round.
  final Duration interval;

  /// Verifies [manifest] at [target]. [markerBytes] is available immediately
  /// after assembly; retry-verification instead uses the recorded marker sha.
  Future<CloudflarePublicationVerification> verify({
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest manifest,
    required int revision,
    List<int> markerBytes = const [],
    List<String> deletedPaths = const [],
  }) async {
    final pending = <String, _Expectation>{};
    void expectContent(String path, CloudflareAssetEntry entry) {
      pending[path] = _Expectation.content(entry);
    }

    final markerEntry = manifest.entryFor(CloudflareLimits.markerPath);
    final booksEntry = manifest.entryFor('books.json');
    if (markerEntry == null || booksEntry == null) {
      return CloudflarePublicationVerification.notVerified;
    }
    pending[CloudflareLimits.markerPath] = _Expectation.content(
      markerEntry,
      exactBytes: markerBytes,
    );
    expectContent('books.json', booksEntry);

    final descriptor = manifest.entryFor('library.json');
    if (descriptor == null) {
      pending['library.json'] = const _Expectation.absent();
    }
    // A complete move/replacement is proven file by file, not inferred from
    // books.json. This covers HTML, descriptor, covers, events and posters.
    for (final entry in manifest.files.entries) {
      if (entry.key != CloudflareLimits.markerPath) {
        expectContent(entry.key, entry.value);
      }
    }
    for (final path in deletedPaths) {
      if (path.startsWith('posters/') && !pending.containsKey(path)) {
        pending[path] = const _Expectation.absent();
      }
    }

    for (var attempt = 0; attempt < attempts && pending.isNotEmpty; attempt++) {
      await _sleep(interval);
      final paths = pending.keys.toList()..sort();
      for (final path in paths) {
        final expectation = pending[path]!;
        final outcome = await _read(
          siteUrl: target.siteUrl,
          path: path,
          maxBytes: expectation.maxBytes,
          cacheBuster: '$revision-$attempt',
        );
        if (expectation.isSatisfiedBy(outcome)) pending.remove(path);
      }
    }
    return pending.isEmpty
        ? CloudflarePublicationVerification.verified
        : CloudflarePublicationVerification.notVerified;
  }

  Future<PublishedSiteReadOutcome> _read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    required String cacheBuster,
  }) async {
    try {
      return await _reader.readOutcome(
        siteUrl: siteUrl,
        path: path,
        maxBytes: maxBytes,
        cacheBuster: cacheBuster,
      );
    } on Exception {
      // Public verification failures are expected and deliberately detail-free.
      return const PublishedSiteReadUnreadable();
    }
  }
}

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

  bool isSatisfiedBy(PublishedSiteReadOutcome outcome) {
    if (expectAbsent) return outcome is PublishedSiteReadAbsent;
    if (outcome is! PublishedSiteReadBody) return false;
    final body = outcome.bytes;
    if (exactBytes.isNotEmpty) return _sameBytes(body, exactBytes);
    return GitBlobSha.of(body) == entry!.sha;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
