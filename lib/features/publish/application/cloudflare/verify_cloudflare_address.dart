/// The narrow manual-subdomain verification deploy (D.2/F.2).
///
/// The app-wide publish queue is ALREADY HELD by the outer setup command. This
/// class never waits for user input and never writes a normal manifest or the
/// journal's verified-live pointer.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/published_file_read_back.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_url.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/cloudflare/unverified_cloudflare_address.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Deploys and proves one fresh `state: verification` marker.
final class VerifyCloudflareAddress {
  /// Creates the verifier over the S6 deploy port and bounded public read-back.
  const VerifyCloudflareAddress({
    required CloudflareDeployApi api,
    required PublishedSiteVerifier verifier,
    required PublishMarkerCodec codec,
    required Future<void> Function(Duration) sleep,
    required int Function() clock,
    String Function()? publishId,
    this.readBackAttempts = PublishedFileReadBack.defaultAttempts,
    this.readBackInterval = PublishedFileReadBack.defaultInterval,
  }) : _api = api,
       _verifier = verifier,
       _codec = codec,
       _sleep = sleep,
       _clock = clock,
       _publishId = publishId ?? PublishMarker.generatePublishId;

  final CloudflareDeployApi _api;
  final PublishedSiteVerifier _verifier;
  final PublishMarkerCodec _codec;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;
  final String Function() _publishId;

  /// Maximum exact-origin marker polls.
  final int readBackAttempts;

  /// Delay between marker polls; injected as zero in tests.
  final Duration readBackInterval;

  /// Verifies [subdomain] at the exact Worker origin.
  ///
  /// [workerExists] and replacement consent were re-checked by the outer queued
  /// command immediately before this call. Existing Workers get the C8 privacy
  /// gate before upload; new Workers get route/privacy configuration after their
  /// first deploy.
  Future<Either<Failure, CloudflarePublishTarget>> call({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareSubdomain subdomain,
    required bool workerExists,
  }) async {
    final candidate = UnverifiedCloudflareAddress.tryParse(
      'https://${workerName.dnsLabel}.${subdomain.value}.workers.dev/',
    );
    if (candidate == null) {
      return left(
        const ValidationFailure(CloudflareErrorMessages.invalidSubdomain),
      );
    }

    try {
      // C8: an existing Worker proves Version URLs off BEFORE a new version.
      if (workerExists) {
        final route = await _api.readWorkerRoute(
          token: token,
          accountId: accountId,
          workerName: workerName,
        );
        await _api.updateWorkerRoute(
          token: token,
          accountId: accountId,
          workerName: workerName,
          enabled: route.enabled,
          previewsEnabled: false,
        );
      }
    } on CloudflareApiException catch (error) {
      return left(CloudflareErrorMessages.fromException(error));
    } on Exception {
      return left(const CloudflareFailure(CloudflareErrorMessages.generic));
    }

    try {
      final marker = PublishMarker(
        publishId: _publishId(),
        publishedAt: _clock(),
        state: PublishMarkerState.verification,
      );
      // This also guards injected/test id generators: an invalid marker is
      // never deployed merely because its bytes could be read back later.
      if (PublishMarker.tryParse(marker.toJson()) == null) {
        return left(const CloudflareFailure(CloudflareErrorMessages.generic));
      }
      final bytes = List<int>.unmodifiable(_codec.encode(marker));
      final path = SitePath.tryParse(CloudflareLimits.markerPath);
      final hash = path == null
          ? null
          : CloudflareAssetHash.forPath(bytes, path);
      if (path == null ||
          hash == null ||
          bytes.length > CloudflareLimits.maxMarkerBytes) {
        return left(const CloudflareFailure(CloudflareErrorMessages.generic));
      }

      final session = await _api.createUploadSession(
        token: token,
        accountId: accountId,
        workerName: workerName,
        manifest: [
          CloudflareAssetManifestEntry(
            path: path,
            hash: hash,
            size: bytes.length,
          ),
        ],
      );
      var completion = session.completionTokenWhenDeduplicated;
      for (final bucket in session.buckets) {
        final assets = <CloudflareBucketAsset>[];
        for (final requestedHash in bucket) {
          if (requestedHash != hash) {
            return left(
              CloudflareFailure(
                CloudflareApiExceptionKind.malformedResponse.message,
              ),
            );
          }
          assets.add(
            CloudflareBucketAsset(
              hash: hash,
              type: CloudflareContentType.json,
              size: bytes.length,
              openBytes: () => Stream<List<int>>.value(bytes),
            ),
          );
        }
        completion = await _api.uploadBucket(
          accountId: accountId,
          session: session,
          assets: assets,
        );
      }
      final completionToken = completion;
      if (completionToken == null) {
        return left(
          CloudflareFailure(
            CloudflareApiExceptionKind.malformedResponse.message,
          ),
        );
      }

      await _api.deploy(
        token: token,
        accountId: accountId,
        workerName: workerName,
        completionToken: completionToken,
        kind: CloudflareDeploymentKind.live,
        recovery: () => _recoverDeploy(candidate, marker),
      );
      // This both enables workers.dev and reconfirms Version URLs off after
      // the deploy. Failure is a visible privacy condition, not generic copy.
      try {
        await _api.updateWorkerRoute(
          token: token,
          accountId: accountId,
          workerName: workerName,
          enabled: true,
          previewsEnabled: false,
        );
      } on CloudflareApiException {
        return left(
          CloudflareErrorMessages.duringVerification(
            const CloudflareFailure(CloudflareErrorMessages.versionUrlPrivacy),
          ),
        );
      } on Exception {
        return left(
          CloudflareErrorMessages.duringVerification(
            const CloudflareFailure(CloudflareErrorMessages.versionUrlPrivacy),
          ),
        );
      }

      final served =
          await PublishedFileReadBack(
            verifier: _verifier,
            sleep: _sleep,
            attempts: readBackAttempts,
            interval: readBackInterval,
          ).untilServed(
            siteUrl: candidate.verificationSiteUrl,
            path: CloudflareLimits.markerPath,
            expected: bytes,
            revision: _clock(),
          );
      if (served != true) {
        return left(
          CloudflareErrorMessages.duringVerification(
            const CloudflareFailure(
              'Cloudflare did not serve the expected verification marker.',
            ),
          ),
        );
      }

      // C9: only now may the candidate be parsed as a confirmed address. The
      // sealed target is rebuilt from identity parts and cross-checked with it.
      final confirmed = CloudflareSiteUrl.tryParse(
        candidate.verificationSiteUrl,
      );
      final target = CloudflarePublishTarget.create(
        accountId: accountId.value,
        workerName: workerName.value,
        accountSubdomain: subdomain.value,
      );
      if (confirmed == null ||
          target == null ||
          target.siteUrl != confirmed.siteUrl) {
        return left(const CloudflareFailure(CloudflareErrorMessages.generic));
      }
      return right(target);
    } on CloudflareApiException catch (error) {
      return left(
        CloudflareErrorMessages.duringVerification(
          CloudflareErrorMessages.fromException(error),
        ),
      );
    } on Exception {
      // Byte-source/codec exceptions can contain no safe user detail either.
      return left(
        CloudflareErrorMessages.duringVerification(
          const CloudflareFailure(CloudflareErrorMessages.generic),
        ),
      );
    }
  }

  Future<CloudflareDeployRecovery> _recoverDeploy(
    UnverifiedCloudflareAddress candidate,
    PublishMarker expected,
  ) async {
    final body = await _verifier.read(
      siteUrl: candidate.verificationSiteUrl,
      path: CloudflareLimits.markerPath,
      maxBytes: CloudflareLimits.maxMarkerBytes,
      cacheBuster: 'recover-${expected.publishId}',
    );
    if (body == null) return CloudflareDeployRecovery.abort;
    final marker = _codec.decode(body);
    if (marker != null &&
        marker.publishId == expected.publishId &&
        marker.state == PublishMarkerState.verification) {
      return CloudflareDeployRecovery.alreadyDeployed;
    }
    // No blind PUT retry: absence, a stale marker, and malformed output are all
    // uncertain rather than proof that the first deploy did not land.
    return CloudflareDeployRecovery.abort;
  }
}
