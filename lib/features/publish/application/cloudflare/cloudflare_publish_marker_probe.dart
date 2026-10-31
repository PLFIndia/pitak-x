/// Structured, exact-origin reads of `pitak-publish.json` (S8/R10).
///
/// A 404 is the only outcome that means ABSENT. A timeout, redirect, oversized
/// body, other HTTP status, or malformed JSON is UNREADABLE; collapsing those
/// cases into absence could turn an unreachable site into an unsafe publish.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Reads and decodes the freshness marker without exposing transport detail.
final class CloudflarePublishMarkerProbe {
  /// Creates the probe over the shared bounded public-read policy.
  ///
  /// [sleep] and [clock] exist for recovery polling: production uses the real
  /// ones, tests pass a no-op sleep and a fixed clock (fix-plan L4).
  const CloudflarePublishMarkerProbe({
    required PublishedSiteReadVerifier reader,
    required PublishMarkerCodec codec,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _reader = reader,
       _codec = codec,
       _sleep = sleep,
       _clock = clock;

  final PublishedSiteReadVerifier _reader;
  final PublishMarkerCodec _codec;
  final Future<void> Function(Duration)? _sleep;
  final int Function()? _clock;

  Future<void> _wait(Duration duration) async {
    final sleep = _sleep;
    if (sleep != null) {
      await sleep(duration);
      return;
    }
    await Future<void>.delayed(duration);
  }

  int _now() => (_clock ?? _systemNow)();

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  /// Reads the marker at [target]'s exact origin. No API token or upload JWT is
  /// involved in this public request.
  Future<PublishMarkerProbe> call({
    required CloudflarePublishTarget target,
    String? cacheBuster,
  }) async {
    final outcome = await _reader.readOutcome(
      siteUrl: target.siteUrl,
      path: CloudflareLimits.markerPath,
      maxBytes: CloudflareLimits.maxMarkerBytes,
      cacheBuster: cacheBuster,
    );
    return switch (outcome) {
      PublishedSiteReadAbsent() => const MarkerAbsent(),
      PublishedSiteReadUnreadable() => const MarkerUnreadable(),
      PublishedSiteReadBody(:final bytes) => switch (_codec.decode(bytes)) {
        final marker? => MarkerPresent(marker),
        null => const MarkerUnreadable(),
      },
    };
  }

  /// Re-reads after an uncertain retirement and accepts only its exact marker.
  Future<CloudflareDeployRecovery> recoverRetirement({
    required CloudflarePublishTarget target,
    required PublishMarker expected,
  }) async {
    try {
      final probe = await call(
        target: target,
        cacheBuster: 'recover-retired-${expected.publishId}',
      );
      if (probe case MarkerPresent(:final marker)) {
        if (marker.publishId == expected.publishId &&
            marker.publishedAt == expected.publishedAt &&
            marker.state == PublishMarkerState.retired) {
          return CloudflareDeployRecovery.alreadyDeployed;
        }
      }
    } on Exception {
      // Uncertainty is never proof that another deployment is safe.
    }
    return CloudflareDeployRecovery.abort;
  }

  /// Re-reads after an uncertain deploy and allows completion only when the
  /// exact fresh live marker is present. Absence/mismatch is never retry proof.
  ///
  /// Polls a few times because a deployment that landed moments ago may not be
  /// visible at the edge yet. It never asks the adapter to re-send the PUT: a
  /// public read cannot prove that an uncertain request will NOT land later,
  /// so re-sending it is never safe (fix-plan L4).
  Future<CloudflareDeployRecovery> recoverLiveDeployment({
    required CloudflarePublishTarget target,
    required PublishMarker expected,
  }) async {
    final started = _now();
    for (
      var attempt = 0;
      attempt < CloudflareLimits.deployRecoveryRounds;
      attempt++
    ) {
      if (attempt > 0) {
        await _wait(CloudflareLimits.deployRecoveryInterval);
      }
      if (_now() - started >=
          CloudflareLimits.deployRecoveryBudget.inMilliseconds) {
        break;
      }
      try {
        final probe = await call(
          target: target,
          cacheBuster: 'recover-${expected.publishId}-$attempt',
        );
        if (probe case MarkerPresent(:final marker)) {
          if (marker.publishId == expected.publishId &&
              marker.state == PublishMarkerState.live) {
            return CloudflareDeployRecovery.alreadyDeployed;
          }
        }
      } on Exception {
        // An unreadable recovery response is not proof a retry is safe.
      }
    }
    return CloudflareDeployRecovery.abort;
  }
}
