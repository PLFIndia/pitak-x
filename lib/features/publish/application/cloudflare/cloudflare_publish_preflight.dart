/// Read-only Cloudflare publish preflight (F.3 steps 1–3).
///
/// No route update, upload session, deployment, credential write, or manifest
/// write happens here. The returned anchor is compared again immediately before
/// deployment; it detects observed staleness but is not cross-device CAS.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';

/// The remote and local state a publish may build against.
final class CloudflarePublishPreflight {
  /// Creates a validated preflight result.
  const CloudflarePublishPreflight({
    required this.target,
    required this.local,
    required this.workerExists,
    required this.route,
    required this.probe,
    required this.freshness,
  });

  /// Exact operation target.
  final CloudflarePublishTarget target;

  /// Valid local record for this target, or the empty record.
  final CloudflareSiteManifest local;

  /// Whether the Worker existence endpoint proved it present.
  final bool workerExists;

  /// Actual route/version settings for an existing Worker; null for a new one.
  final CloudflareWorkerRoute? route;

  /// Structured public marker result.
  final PublishMarkerProbe probe;

  /// Fail-closed freshness classification.
  final PublishFreshness freshness;

  /// Unknown state, a positively identified retired site, and a Worker that
  /// no longer exists all require the complete-snapshot replacement flow
  /// before any write (F.5, F.9, R10).
  bool get requiresReplacement =>
      freshness == PublishFreshness.unknown ||
      freshness == PublishFreshness.knownRetired ||
      freshness == PublishFreshness.siteUnavailable;

  /// True only for a new Worker with no matching local record and a real 404.
  bool get isNewSite => freshness == PublishFreshness.newSite;

  /// The remote facts a confirmation or replacement is bound to.
  CloudflareRemoteAnchor get anchor => switch (probe) {
    MarkerAbsent() => CloudflareRemoteAnchor(
      workerExists: workerExists,
      markerKind: CloudflareMarkerKind.absent,
    ),
    MarkerUnreadable() => CloudflareRemoteAnchor(
      workerExists: workerExists,
      markerKind: CloudflareMarkerKind.unreadable,
    ),
    MarkerPresent(:final marker) => CloudflareRemoteAnchor(
      workerExists: workerExists,
      markerKind: CloudflareMarkerKind.present,
      publishId: marker.publishId,
      markerState: marker.state,
    ),
  };

  /// The same remote facts with [local] as the record to build from.
  ///
  /// Used when a pending deploy is promoted: the marker proved that deployment
  /// landed, so freshness must be re-derived against the record describing it
  /// (fix-plan L4). Nothing remote is re-read.
  CloudflarePublishPreflight withLocal(CloudflareSiteManifest local) =>
      CloudflarePublishPreflight(
        target: target,
        local: local,
        workerExists: workerExists,
        route: route,
        probe: probe,
        freshness: classifyFreshness(
          localState: local.target == null ? null : local.state,
          localPublishId: local.publishId,
          probe: probe,
          workerExists: workerExists,
        ),
      );

  /// True when the public marker is EXACTLY the deploy [manifest] attempted.
  ///
  /// This is the only evidence that promotes a pending record (fix-plan L4):
  /// a different id means the attempt did not land, and an unreadable marker
  /// proves nothing.
  bool provesDeploymentOf(CloudflareSiteManifest manifest) {
    if (manifest.target == null || manifest.publishId == null) return false;
    final marker = switch (probe) {
      MarkerPresent(:final marker) => marker,
      // Only a positive, live marker counts; absence or unreadability does not.
      _ => null,
    };
    return marker != null &&
        marker.publishId == manifest.publishId &&
        marker.state == PublishMarkerState.live;
  }

  /// Compares the target and the remote anchor. Route settings are deliberately
  /// excluded: the C8 gate changes them on purpose.
  bool hasSameAnchor(CloudflarePublishPreflight other) =>
      target.targetId == other.target.targetId &&
      target.siteUrl == other.target.siteUrl &&
      anchor.matches(other.anchor);
}

/// Reads account, Worker, route, and marker state without writing anything.
final class CloudflarePublishPreflightReader {
  /// Creates the reader over the segregated API roles and structured probe.
  const CloudflarePublishPreflightReader({
    required CloudflareAccountApi accountApi,
    required CloudflareDeployApi deployApi,
    required CloudflarePublishMarkerProbe markerProbe,
  }) : _accountApi = accountApi,
       _deployApi = deployApi,
       _markerProbe = markerProbe;

  final CloudflareAccountApi _accountApi;
  final CloudflareDeployApi _deployApi;
  final CloudflarePublishMarkerProbe _markerProbe;

  /// Runs the read-only preflight for [target].
  Future<Either<Failure, CloudflarePublishPreflight>> call({
    required CloudflareApiToken token,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest local,
    required String cacheBuster,
  }) async {
    try {
      // A 403 is the documented manual-address limitation, not drift. Any
      // explicit readable absence or different subdomain is SiteUnavailable.
      try {
        final subdomain = await _accountApi.readAccountSubdomain(
          token: token,
          accountId: target.accountId,
        );
        if (subdomain == null ||
            subdomain.value != target.accountSubdomain.value) {
          return const Left(
            CloudflareFailure(CloudflareErrorMessages.siteUnavailable),
          );
        }
      } on CloudflareApiException catch (error) {
        if (error.kind != CloudflareApiExceptionKind.forbidden) rethrow;
      }

      final workerExists = await _deployApi.workerExists(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
      );
      final probe = await _markerProbe.call(
        target: target,
        cacheBuster: cacheBuster,
      );
      final route = workerExists
          ? await _deployApi.readWorkerRoute(
              token: token,
              accountId: target.accountId,
              workerName: target.workerName,
            )
          : null;
      final freshness = classifyFreshness(
        localState: local.target == null ? null : local.state,
        localPublishId: local.publishId,
        probe: probe,
        workerExists: workerExists,
      );
      return Right(
        CloudflarePublishPreflight(
          target: target,
          local: local,
          workerExists: workerExists,
          route: route,
          probe: probe,
          freshness: freshness,
        ),
      );
    } on CloudflareApiException catch (error) {
      return Left(CloudflareErrorMessages.fromException(error));
    } on Exception {
      return const Left(CloudflareFailure(CloudflareErrorMessages.generic));
    }
  }
}
