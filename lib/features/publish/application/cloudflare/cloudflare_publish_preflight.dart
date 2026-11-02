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
    bool? workerHasContent,
  }) : workerHasContent = workerHasContent ?? workerExists;

  /// Exact operation target.
  final CloudflarePublishTarget target;

  /// Valid local record for this target, or the empty record.
  final CloudflareSiteManifest local;

  /// Whether the Worker existence endpoint proved it present.
  ///
  /// Used for FACTS (the anchor, the RH1 race checks, the route read): an
  /// empty Worker exists.
  final bool workerExists;

  /// Whether the Worker has at least one version, i.e. serves content.
  ///
  /// Used for CONTENT decisions (freshness): an empty Worker (no versions,
  /// what an interrupted first publish leaves) holds nothing that a publish
  /// could destroy, so it classifies like a Worker that does not exist and
  /// never asks to "replace" it (handoff §12, 2026-10-30). Defaults to
  /// [workerExists] for callers that only know existence.
  final bool workerHasContent;

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
        workerHasContent: workerHasContent,
        route: route,
        probe: probe,
        freshness: classifyFreshness(
          localState: local.target == null ? null : local.state,
          localPublishId: local.publishId,
          probe: probe,
          workerExists: workerHasContent,
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
  ///
  /// Speed (plan SP3): the subdomain read, the Worker-presence read and the
  /// marker probe do not depend on each other, so they start together; the
  /// route read starts as soon as presence shows the Worker exists. The
  /// answers are then checked in the order the reads used to run one after
  /// another (subdomain, presence, marker, route), so the result and every
  /// failure are exactly what that order produced.
  ///
  /// One difference, on failure paths only (beginner note): when an early
  /// check fails — for example the account's workers.dev address changed —
  /// the later reads were already sent. They are reads (nothing is written),
  /// and their answers are ignored. On every successful run the requests are
  /// exactly the same as before.
  Future<Either<Failure, CloudflarePublishPreflight>> call({
    required CloudflareApiToken token,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest local,
    required String cacheBuster,
  }) async {
    final subdomainRead = _capture(
      () => _accountApi.readAccountSubdomain(
        token: token,
        accountId: target.accountId,
      ),
    );
    final presenceRead = _capture(
      () => _deployApi.workerPresence(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
      ),
    );
    final markerRead = _capture(
      () => _markerProbe.call(target: target, cacheBuster: cacheBuster),
    );
    // The route belongs to an existing Worker only, so it still waits for
    // presence. Null means "not read" (absent Worker, or presence failed).
    final routeRead = presenceRead.then(
      (presence) => switch (presence) {
        _Answered(:final value) when value.exists => _capture(
          () => _deployApi.readWorkerRoute(
            token: token,
            accountId: target.accountId,
            workerName: target.workerName,
          ),
        ),
        _ => Future<_ReadResult<CloudflareWorkerRoute>?>.value(),
      },
    );
    // Every read is awaited before any answer is checked: a check that ends
    // the preflight early must not leave a read nobody listens to.
    final (subdomainResult, presenceResult, markerResult, routeResult) = await (
      subdomainRead,
      presenceRead,
      markerRead,
      routeRead,
    ).wait;

    try {
      // A 403 is the documented manual-address limitation, not drift. Any
      // explicit readable absence or different subdomain is SiteUnavailable.
      try {
        final subdomain = subdomainResult.valueOrThrow();
        if (subdomain == null ||
            subdomain.value != target.accountSubdomain.value) {
          return const Left(
            CloudflareFailure(CloudflareErrorMessages.siteUnavailable),
          );
        }
      } on CloudflareApiException catch (error) {
        if (error.kind != CloudflareApiExceptionKind.forbidden) rethrow;
      }

      final presence = presenceResult.valueOrThrow();
      // No case-variant listing here any more: Cloudflare refuses a Worker
      // name with capitals (HTTP 400, code 10016, real host 2026-10-30), so no
      // differently-capitalised Worker can own this lower-case address.
      final workerExists = presence.exists;
      final probe = markerResult.valueOrThrow();
      // `routeResult` is non-null exactly when the Worker exists (above).
      final route = workerExists ? routeResult!.valueOrThrow() : null;
      // Content, not existence, decides freshness: an empty Worker classifies
      // like an absent one (see `workerHasContent`).
      final freshness = classifyFreshness(
        localState: local.target == null ? null : local.state,
        localPublishId: local.publishId,
        probe: probe,
        workerExists: presence.hasContent,
      );
      return Right(
        CloudflarePublishPreflight(
          target: target,
          local: local,
          workerExists: workerExists,
          workerHasContent: presence.hasContent,
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

  /// Runs [read] and keeps what it produced: its value, or the exception it
  /// threw. The exception is NOT swallowed: [call] throws it again, with its
  /// stack trace, at the point where the one-by-one order would have met it.
  /// An `Error` (a bug) is not caught and propagates as before.
  static Future<_ReadResult<T>> _capture<T>(Future<T> Function() read) async {
    try {
      return _Answered(await read());
    } on Exception catch (error, stackTrace) {
      return _Threw(error, stackTrace);
    }
  }
}

/// What one concurrent preflight read produced (plan SP3).
///
/// Why a small sealed type (beginner note): the reads now run side by side,
/// but their failures must still be judged in the old order. Keeping each
/// result lets [CloudflarePublishPreflightReader.call] look at them one by
/// one, exactly like the sequential code did.
sealed class _ReadResult<T> {
  const _ReadResult();

  /// The value, or the read's exception thrown again with its stack trace.
  T valueOrThrow();
}

final class _Answered<T> extends _ReadResult<T> {
  const _Answered(this.value);

  final T value;

  @override
  T valueOrThrow() => value;
}

final class _Threw<T> extends _ReadResult<T> {
  const _Threw(this.error, this.stackTrace);

  final Exception error;
  final StackTrace stackTrace;

  @override
  T valueOrThrow() => Error.throwWithStackTrace(error, stackTrace);
}
