/// Upload → deploy → read-back tail of a Cloudflare publish (F.3).
///
/// Split out of the orchestrator (fix-plan Phase 0) so the publish use case
/// keeps only orchestration. The app-wide operation queue is already held by
/// the caller; this pipeline never waits for a dialog.
///
/// Two publishes share it: the ordinary catalogue/events publish and the
/// availability lane (ADR 0019 Decision 11). Every gate below (Version URLs
/// off, the session baseline, the final anchor check, the pending record
/// before the PUT) runs for both, unchanged. The two differ only in what the
/// caller passes: which files the read-back must see, and what happens when
/// Cloudflare asks for bytes this phone does not have. The pipeline itself
/// knows nothing about whole-site replacements, so it cannot start one.
library;

import 'package:pitaka/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_session_baseline.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_version_url_gate.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Runs the remote-write half of one publish against a prepared snapshot.
final class CloudflareDeployPipeline {
  /// Creates the pipeline over the shared deploy ports and local record.
  const CloudflareDeployPipeline({
    required CloudflareDeployApi deployApi,
    required CloudflareManifestStore manifest,
    required CloudflarePublishPreflightReader preflight,
    required CloudflarePublishMarkerProbe markerProbe,
    required CloudflarePublicationVerifier verifier,
    required CloudflareVerifiedStateCommit verifiedCommit,
    required int Function() clock,
  }) : _deployApi = deployApi,
       _manifest = manifest,
       _preflight = preflight,
       _markerProbe = markerProbe,
       _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _clock = clock;

  final CloudflareDeployApi _deployApi;
  final CloudflareManifestStore _manifest;
  final CloudflarePublishPreflightReader _preflight;
  final CloudflarePublishMarkerProbe _markerProbe;
  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final int Function() _clock;

  /// Uploads the prepared artifacts, deploys, and proves the result.
  ///
  /// [initial] is the preflight the operation was prepared against; it is
  /// compared with a fresh read immediately before the deploy.
  ///
  /// [readBack] says which files prove this deploy, and picks the matching
  /// after-deploy budget. [resultUrl] is the address a success reports.
  ///
  /// [onLocalBytesMissing] decides what this operation reports when
  /// Cloudflare asks for a hash this phone has no bytes for (nothing was
  /// deployed then). The ordinary publish offers a reviewed whole-site
  /// replacement; a replacement, which already carries every byte, reports
  /// the failure; the availability lane must never replace a site, so it asks
  /// the user to repair it (ADR 0019 Decision 11).
  ///
  /// [timings] is the CALLER's recorder (plan S0, instrumented builds only):
  /// the Cloudflare use case owns it, so one publish produces one log line
  /// carrying this pipeline's upload / deploy / read-back marks. Null ⇒ no
  /// timing at all.
  Future<PublishResult> run({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
    required CloudflareSiteManifest local,
    required CloudflarePublishPreflight initial,
    required CloudflarePublicationArtifacts publication,
    required CloudflareReadBackScope readBack,
    required String resultUrl,
    required Future<PublishResult> Function() onLocalBytesMissing,
    required bool availabilityOmitted,
    required CloudflarePublishOperationProgress progress,
    PublishTimingRecorder? timings,
  }) async {
    final token = connection.useToken((value) => value);
    final gate = CloudflareVersionUrlGate(deployApi: _deployApi);
    if (initial.workerExists) {
      final route = initial.route;
      if (route == null) {
        return const PublishFailure(CloudflareErrorMessages.artifactInvalid);
      }
      final private = await gate.ensureOff(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
        route: route,
      );
      if (!private) {
        return const PublishFailure(CloudflareErrorMessages.versionUrlPrivacy);
      }
    }

    // RH1: creating the session may create the Worker. A Worker that appeared
    // BEFORE the session is someone else's, so this publish stops as stale.
    if (await CloudflareSessionBaseline.workerAppeared(
      sawWorkerInitially: initial.workerExists,
      workerExists: () => _deployApi.workerExists(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
      ),
    )) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }

    final session = await _deployApi.createUploadSession(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: publication.uploadManifest,
    );

    // RH1: adopt our own session's Worker creation as the baseline, or keep
    // the old baseline when a foreign marker appeared.
    final baselineResult = await CloudflareSessionBaseline.afterSession(
      initial: initial,
      read: () => _preflight.call(
        token: token,
        target: target,
        local: local,
        cacheBuster: 'post-session-${_clock()}',
      ),
    );
    final baselineFailure = baselineResult.swap().toNullable();
    if (baselineFailure != null) {
      return CloudflarePublishOutcomes.failure(baselineFailure);
    }
    final baseline = baselineResult.toNullable()!;
    final uploadStartedAt = timings?.begin();
    final upload = await CloudflareBucketUploader(_deployApi).upload(
      accountId: target.accountId,
      session: session,
      assetForHash: publication.assetForHash,
      beforeBucketUpload: () => progress.assetBytesMayHaveUploaded = true,
    );
    final CloudflareBucketsUploaded uploaded;
    switch (upload) {
      case CloudflareBucketsUploaded():
        uploaded = upload;
      case CloudflareBucketHashMissing():
        return onLocalBytesMissing();
      case CloudflareUploadNotConfirmed():
        return PublishFailure(
          CloudflarePublishOutcomes.uploadNotConfirmed(progress),
        );
    }
    final completionToken = uploaded.completion;
    final uploadedPaths = [
      for (final hash in uploaded.uploadedHashes)
        ...publication.pathsForHash(hash),
    ];
    if (timings != null) {
      timings.end(
        PublishTimingStage.upload,
        uploadStartedAt,
        bytes: uploaded.uploadedHashes.fold<int>(
          0,
          (sum, hash) => sum + (publication.assetForHash(hash)?.size ?? 0),
        ),
      );
    }

    final last = await _preflight.call(
      token: token,
      target: target,
      local: local,
      cacheBuster: 'final-${_clock()}',
    );
    final lastFailure = last.swap().toNullable();
    if (lastFailure != null) {
      return CloudflarePublishOutcomes.failure(lastFailure);
    }
    if (!baseline.hasSameAnchor(last.toNullable()!)) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }

    // L3: the route is re-read immediately before the deploy, so this is the
    // last honest moment to prove Version URLs are still private. A failure
    // here stops before the PUT; it never deploys an exposed version.
    final lastCheck = last.toNullable()!;
    if (lastCheck.workerExists && lastCheck.route != null) {
      try {
        final private = await gate.ensureOff(
          token: token,
          accountId: target.accountId,
          workerName: target.workerName,
          route: lastCheck.route,
        );
        if (!private) {
          return const PublishFailure(
            CloudflareErrorMessages.versionUrlPrivacy,
          );
        }
      } on CloudflareApiException {
        return const PublishFailure(CloudflareErrorMessages.versionUrlPrivacy);
      }
    }

    // L4: the new publish id exists only in this PUT, so record the attempt
    // first. A phone that cannot describe the attempt could never recognise a
    // deploy whose response was lost, and would offer a whole-site
    // replacement for its own site.
    final pending = _manifest.savePending(publication.manifest);
    if (pending.isLeft()) {
      return const PublishFailure(
        CloudflareErrorMessages.localRecordNotSavedBeforeDeploy,
      );
    }

    final deployStartedAt = timings?.begin();
    progress.deployStarted = true;
    await _deployApi.deploy(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      completionToken: completionToken,
      kind: CloudflareDeploymentKind.live,
      recovery: () => _markerProbe.recoverLiveDeployment(
        target: target,
        expected: publication.marker,
      ),
    );
    progress.deployAccepted = true;
    timings?.end(PublishTimingStage.deploy, deployStartedAt);

    final deployedSaved = _manifest.save(publication.manifest);
    var localStateSaved = deployedSaved.isRight();
    if (localStateSaved) {
      // Clearing the attempt is idempotent: a leftover record is promoted only
      // by an exact marker match, so a failed clear cannot corrupt the next
      // publish. Its failure is therefore not a user-visible outcome.
      _manifest.clearPending();
    }
    try {
      final private = await gate.afterDeploy(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
      );
      if (!private) {
        return PublishFailure(
          CloudflarePublishOutcomes.privacyAfterDeploy(
            localStateSaved: localStateSaved,
          ),
          // Retry verification may disable Version URLs and then prove the
          // deployment, so it is the honest next step (D8/L3).
          canRetryVerification: true,
        );
      }
    } on Exception {
      return PublishFailure(
        CloudflarePublishOutcomes.privacyAfterDeploy(
          localStateSaved: localStateSaved,
        ),
        canRetryVerification: true,
      );
    }

    final readBackStartedAt = timings?.begin();
    var readBackRounds = 0;
    final verified = await _verifier.verify(
      target: target,
      manifest: publication.manifest,
      markerBytes: publication.markerBytes,
      deletedPaths: publication.deletedPaths,
      revision: _clock(),
      scope: readBack,
      budget: switch (readBack) {
        CloudflareReadBackScope.ordinary =>
          CloudflareReadBackBudget.afterDeploy,
        // AV13: the first round reads at once (two tiny files).
        CloudflareReadBackScope.availabilityOnly =>
          CloudflareReadBackBudget.afterAvailabilityDeploy,
      },
      onRounds: (timings?.enabled ?? false)
          ? (rounds) => readBackRounds = rounds
          : null,
    );
    if (timings != null) {
      timings.end(
        PublishTimingStage.readBack,
        readBackStartedAt,
        rounds: timings.enabled ? readBackRounds : null,
      );
    }
    if (verified == CloudflarePublicationVerification.verified) {
      final committed = await _verifiedCommit.call(
        connection: connection,
        target: target,
        manifest: publication.manifest,
      );
      localStateSaved = committed.isRight();
    }
    return PublishSuccess(
      pagesUrl: resultUrl,
      uploadedPaths: List.unmodifiable(uploadedPaths.toSet()),
      availabilityOmitted: availabilityOmitted,
      pagesLive: verified == CloudflarePublicationVerification.verified
          ? true
          : null,
      localStateSaved: localStateSaved,
    );
  }
}
