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
  const CloudflarePublishMarkerProbe({
    required PublishedSiteReadVerifier reader,
    required PublishMarkerCodec codec,
  }) : _reader = reader,
       _codec = codec;

  final PublishedSiteReadVerifier _reader;
  final PublishMarkerCodec _codec;

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
  Future<CloudflareDeployRecovery> recoverLiveDeployment({
    required CloudflarePublishTarget target,
    required PublishMarker expected,
  }) async {
    try {
      final probe = await call(
        target: target,
        cacheBuster: 'recover-${expected.publishId}',
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
    return CloudflareDeployRecovery.abort;
  }
}
