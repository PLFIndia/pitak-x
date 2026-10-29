/// Upload → deploy → read-back tail of an ordinary Cloudflare publish (F.3).
///
/// Split out of the orchestrator (fix-plan Phase 0) so the publish use case
/// keeps only orchestration. The app-wide operation queue is already held by
/// the caller; this pipeline never waits for a dialog.
library;

import 'package:pitaka/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_replacement_preparation.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_version_url_gate.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
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
    required CloudflareReplacementPreparation replacement,
    required PublishReads reads,
    required int Function() clock,
  }) : _deployApi = deployApi,
       _manifest = manifest,
       _preflight = preflight,
       _markerProbe = markerProbe,
       _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _replacement = replacement,
       _reads = reads,
       _clock = clock;

  final CloudflareDeployApi _deployApi;
  final CloudflareManifestStore _manifest;
  final CloudflarePublishPreflightReader _preflight;
  final CloudflarePublishMarkerProbe _markerProbe;
  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final CloudflareReplacementPreparation _replacement;
  final PublishReads _reads;
  final int Function() _clock;

  /// Uploads the prepared artifacts, deploys, and proves the result.
  ///
  /// [initial] is the preflight the operation was prepared against; it is
  /// compared with a fresh read immediately before the deploy.
  Future<PublishResult> run({
    required CloudflareConnection connection,
    required CloudflarePublishTarget target,
    required PublishRequestedSection section,
    required CloudflareSiteManifest local,
    required CloudflarePublishPreflight initial,
    required CloudflarePublicationArtifacts publication,
    required PublishInputs inputs,
    required bool replacing,
    required bool availabilityOmitted,
    required CloudflarePublishOperationProgress progress,
  }) async {
    final gate = CloudflareVersionUrlGate(deployApi: _deployApi);
    if (initial.workerExists) {
      final route = initial.route;
      if (route == null) {
        return const PublishFailure(CloudflareErrorMessages.artifactInvalid);
      }
      final private = await gate.ensureOff(
        token: connection.useToken((token) => token),
        accountId: target.accountId,
        workerName: target.workerName,
        route: route,
      );
      if (!private) {
        return const PublishFailure(CloudflareErrorMessages.versionUrlPrivacy);
      }
    }

    final session = await _deployApi.createUploadSession(
      token: connection.useToken((token) => token),
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: publication.uploadManifest,
    );
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
      case CloudflareBucketHashMissing() when !replacing:
        return _replacement.prepareResult(
          reads: _reads,
          target: target,
          requestedSection: section,
          inputs: inputs,
        );
      case CloudflareBucketHashMissing():
        return PublishFailure(
          '${CloudflareErrorMessages.missingRequestedHash} '
          '${progress.assetBytesNote}',
        );
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

    final last = await _preflight.call(
      token: connection.useToken((token) => token),
      target: target,
      local: local,
      cacheBuster: 'final-${_clock()}',
    );
    final lastFailure = last.swap().toNullable();
    if (lastFailure != null) {
      return CloudflarePublishOutcomes.failure(lastFailure);
    }
    if (!initial.hasSameAnchor(last.toNullable()!)) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }

    progress.deployStarted = true;
    await _deployApi.deploy(
      token: connection.useToken((token) => token),
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

    var localStateSaved = _manifest.save(publication.manifest).isRight();
    try {
      final private = await gate.afterDeploy(
        token: connection.useToken((token) => token),
        accountId: target.accountId,
        workerName: target.workerName,
      );
      if (!private) {
        return PublishFailure(
          CloudflarePublishOutcomes.privacyAfterDeploy(
            localStateSaved: localStateSaved,
          ),
        );
      }
    } on Exception {
      return PublishFailure(
        CloudflarePublishOutcomes.privacyAfterDeploy(
          localStateSaved: localStateSaved,
        ),
      );
    }

    final verified = await _verifier.verify(
      target: target,
      manifest: publication.manifest,
      markerBytes: publication.markerBytes,
      deletedPaths: publication.deletedPaths,
      revision: _clock(),
    );
    if (verified == CloudflarePublicationVerification.verified) {
      final committed = await _verifiedCommit.call(
        connection: connection,
        target: target,
        manifest: publication.manifest,
      );
      localStateSaved = committed.isRight();
    }
    return PublishSuccess(
      pagesUrl: CloudflarePublishOutcomes.resultUrl(target, section),
      uploadedPaths: List.unmodifiable(uploadedPaths.toSet()),
      availabilityOmitted: availabilityOmitted,
      pagesLive: verified == CloudflarePublicationVerification.verified
          ? true
          : null,
      localStateSaved: localStateSaved,
    );
  }
}
