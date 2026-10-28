/// Exact-origin read-back for a moved old site (R16/F.6).
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Verifies the moved root, old books.json 404, and exact retired marker when
/// the source is Cloudflare. No redirect, foreign origin, or marker 404 counts.
final class MovedSiteVerifier {
  /// Creates the grouped bounded verifier.
  const MovedSiteVerifier({
    required PublishedSiteReadVerifier reader,
    required PublishMarkerCodec markerCodec,
    required MovedHtmlValidationFn validateMovedHtml,
    required Future<void> Function(Duration) sleep,
    this.attempts = 12,
    this.interval = const Duration(seconds: 5),
  }) : _reader = reader,
       _markerCodec = markerCodec,
       _validateMovedHtml = validateMovedHtml,
       _sleep = sleep;

  final PublishedSiteReadVerifier _reader;
  final PublishMarkerCodec _markerCodec;
  final MovedHtmlValidationFn _validateMovedHtml;
  final Future<void> Function(Duration) _sleep;

  /// Maximum grouped polling rounds.
  final int attempts;

  /// Delay before each polling round.
  final Duration interval;

  /// Returns true only when every old-site requirement is proven.
  Future<bool> verify(PendingMove pending, {required int revision}) async {
    if (!await _validateMovedHtml(pending)) return false;
    final descriptor = pending.retirement;
    final expectations = <String, _MovedExpectation>{
      '': _MovedExpectation.content(descriptor.indexHtml),
      'books.json': const _MovedExpectation.absent(),
    };
    final marker = descriptor.marker;
    if (pending.oldTarget is CloudflarePublishTarget && marker != null) {
      expectations[CloudflareLimits.markerPath] = _MovedExpectation.content(
        _markerCodec.encode(marker),
      );
    }

    for (
      var attempt = 0;
      attempt < attempts && expectations.isNotEmpty;
      attempt++
    ) {
      await _sleep(interval);
      for (final path in expectations.keys.toList()) {
        final expectation = expectations[path]!;
        final outcome = await _read(
          siteUrl: pending.oldTarget.siteUrl,
          path: path,
          maxBytes: expectation.maxBytes,
          cacheBuster: '$revision-$attempt',
        );
        if (expectation.isSatisfiedBy(outcome)) expectations.remove(path);
      }
    }
    return expectations.isEmpty;
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
      return const PublishedSiteReadUnreadable();
    }
  }
}

final class _MovedExpectation {
  const _MovedExpectation.content(this.bytes) : expectAbsent = false;
  const _MovedExpectation.absent() : bytes = null, expectAbsent = true;

  final List<int>? bytes;
  final bool expectAbsent;

  int get maxBytes {
    if (expectAbsent) return 1;
    final length = bytes!.length;
    return length == 0 ? 1 : length;
  }

  bool isSatisfiedBy(PublishedSiteReadOutcome outcome) {
    if (expectAbsent) return outcome is PublishedSiteReadAbsent;
    if (outcome is! PublishedSiteReadBody) return false;
    final actual = outcome.bytes;
    final expected = bytes!;
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }
}
