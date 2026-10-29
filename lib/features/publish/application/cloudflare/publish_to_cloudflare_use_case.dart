/// Ordinary Cloudflare catalogue/events publishing and R4 replacement (S8/F.3).
///
/// The app-wide operation queue is ALREADY HELD by the outer controller. This
/// use case never waits for a dialog and never enqueues nested work.
/// Preparation returns a typed replacement summary without a remote write;
/// confirmation
/// re-enters through the controller with only a safe target/section/digest.
library;

import 'package:flutter/foundation.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_replacement_preparation.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// One DI wiring; only the strict-read implementation varies by entry point.
typedef PublishToCloudflareUseCaseFactory =
    PublishToCloudflareUseCase Function(PublishReads reads);

/// Orchestrates one ordinary publish or verification-only retry.
final class PublishToCloudflareUseCase {
  /// Creates the use case over operation-scoped ports and factories.
  const PublishToCloudflareUseCase({
    required CloudflareDeployApi deployApi,
    required CloudflareCredentialStore credentials,
    required CloudflareManifestStore manifest,
    required PublishSnapshotBuilder snapshotBuilder,
    required PublishReads reads,
    required CloudflarePublishPreflightReader preflight,
    required CloudflarePublishMarkerProbe markerProbe,
    required CloudflareReplacementPreparation replacement,
    required CloudflareArtifactStoreFactory artifactStores,
    required PublishMarkerCodec markerCodec,
    required CloudflarePublicationVerifier verifier,
    required CloudflareVerifiedStateCommit verifiedCommit,
    required int Function() clock,
    String Function()? publishId,
  }) : _deployApi = deployApi,
       _credentials = credentials,
       _manifest = manifest,
       _snapshotBuilder = snapshotBuilder,
       _reads = reads,
       _preflight = preflight,
       _markerProbe = markerProbe,
       _replacement = replacement,
       _artifactStores = artifactStores,
       _markerCodec = markerCodec,
       _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _clock = clock,
       _publishId = publishId ?? PublishMarker.generatePublishId;

  final CloudflareDeployApi _deployApi;
  final CloudflareCredentialStore _credentials;
  final CloudflareManifestStore _manifest;
  final PublishSnapshotBuilder _snapshotBuilder;
  final PublishReads _reads;
  final CloudflarePublishPreflightReader _preflight;
  final CloudflarePublishMarkerProbe _markerProbe;
  final CloudflareReplacementPreparation _replacement;
  final CloudflareArtifactStoreFactory _artifactStores;
  final PublishMarkerCodec _markerCodec;
  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final int Function() _clock;
  final String Function() _publishId;

  /// Runs with the queue already held. [confirmation] is the exact summary
  /// returned earlier; changed content produces a new summary instead of using
  /// stale bytes. [verificationOnly] can never create an upload or deployment.
  Future<PublishResult> call({
    required CloudflarePublishTarget target,
    required PublishRequestedSection section,
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    final store = _artifactStores();
    final sink = CloudflareArtifactSink(store);
    final snapshotBuilder = _snapshotBuilder.withArtifactSink(sink);
    final replacement = _replacement.withArtifactStore(store);
    final progress = CloudflarePublishOperationProgress();
    PublishResult? result;
    try {
      result = await _run(
        target: target,
        section: section,
        confirmation: confirmation,
        verificationOnly: verificationOnly,
        store: store,
        snapshotBuilder: snapshotBuilder,
        replacement: replacement,
        progress: progress,
      );
    } on CloudflareApiException catch (error, stackTrace) {
      // Safe smoke diagnostics: numeric/category data and method names only.
      // Never log bearer tokens, JWTs, URLs, response bodies, or library data.
      debugPrint(
        'CloudflarePublish API failure: ${error.kind.name}; '
        'status=${error.statusCode}; codes=${error.errorCodes}; '
        'deployStarted=${progress.deployStarted}; '
        'deployAccepted=${progress.deployAccepted}',
      );
      debugPrintStack(stackTrace: stackTrace, label: 'CloudflarePublish stack');
      result = PublishFailure(
        CloudflarePublishOutcomes.transport(
          error,
          assetBytesMayHaveUploaded: progress.assetBytesMayHaveUploaded,
          deployStarted: progress.deployStarted,
          deployAccepted: progress.deployAccepted,
        ),
      );
    } on Exception {
      result = PublishFailure(
        CloudflarePublishOutcomes.unexpected(
          assetBytesMayHaveUploaded: progress.assetBytesMayHaveUploaded,
          deployStarted: progress.deployStarted,
          deployAccepted: progress.deployAccepted,
        ),
      );
    } finally {
      final cleanup = await store.dispose();
      if (cleanup.isLeft() && result != null) {
        result = CloudflarePublishOutcomes.cleanupFailed(result);
      }
    }
    return result!;
  }

  Future<PublishResult> _run({
    required CloudflarePublishTarget target,
    required PublishRequestedSection section,
    required PublishReplacementSummary? confirmation,
    required bool verificationOnly,
    required CloudflareArtifactStore store,
    required PublishSnapshotBuilder snapshotBuilder,
    required CloudflareReplacementPreparation replacement,
    required CloudflarePublishOperationProgress progress,
  }) async {
    if (confirmation != null &&
        (confirmation.target.targetId != target.targetId ||
            confirmation.target.siteUrl != target.siteUrl ||
            confirmation.requestedSection != section)) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }

    var inputs = await replacement.readInputs(
      reads: _reads,
      target: target,
      section: section,
      complete: confirmation != null,
    );
    if (inputs == null) return const PublishFailure(_readFailed);

    final loaded = await _credentials.read();
    final credentialFailure = loaded.swap().toNullable();
    if (credentialFailure != null) {
      return CloudflarePublishOutcomes.failure(credentialFailure);
    }
    final connection = loaded.toNullable();
    if (connection == null) {
      return const PublishFailure(CloudflareErrorMessages.connectionRequired);
    }
    final currentTarget = connection.status.target;
    if (currentTarget == null ||
        currentTarget.targetId != target.targetId ||
        currentTarget.siteUrl != target.siteUrl) {
      return const PublishFailure(CloudflareErrorMessages.targetMismatch);
    }

    var local = _manifest.load();
    if (local.target != null &&
        (!local.describes(target) ||
            !CloudflareSiteManifest.isValidFileSet(
              state: local.state,
              paths: local.ownedPaths,
            ))) {
      return const PublishFailure(CloudflareErrorMessages.targetMismatch);
    }

    final preflight = await _preflight.call(
      token: connection.useToken((token) => token),
      target: target,
      local: local,
      cacheBuster: 'preflight-${_clock()}',
    );
    final preflightFailure = preflight.swap().toNullable();
    if (preflightFailure != null) {
      return CloudflarePublishOutcomes.failure(preflightFailure);
    }
    final initial = preflight.toNullable()!;
    if (initial.freshness == PublishFreshness.siteUnavailable) {
      return const PublishFailure(CloudflareErrorMessages.siteUnavailable);
    }

    if (initial.freshness == PublishFreshness.known) {
      if (local.state == PublishState.deployed) {
        final verified = await _verifier.verify(
          target: target,
          manifest: local,
          revision: _clock(),
        );
        if (verified != CloudflarePublicationVerification.verified) {
          return const PublishFailure(
            CloudflareErrorMessages.publicationVerificationFailed,
          );
        }
        final committed = await _verifiedCommit.call(
          connection: connection,
          target: target,
          manifest: local,
        );
        if (verificationOnly || committed.isLeft()) {
          return CloudflarePublishOutcomes.verificationSuccess(
            target,
            localStateSaved: committed.isRight(),
          );
        }
        local = local.asLive();
      } else if (_verifiedCommit.needsRepair(
        connection: connection,
        target: target,
        manifest: local,
      )) {
        // A local `live` record says an earlier read-back succeeded, but a
        // missing journal/connection flag means that commit may have crashed.
        // Re-prove the exact public snapshot before repairing either record.
        final verified = await _verifier.verify(
          target: target,
          manifest: local,
          revision: _clock(),
        );
        if (verified != CloudflarePublicationVerification.verified) {
          return const PublishFailure(
            CloudflareErrorMessages.publicationVerificationFailed,
          );
        }
        final committed = await _verifiedCommit.call(
          connection: connection,
          target: target,
          manifest: local,
        );
        if (verificationOnly || committed.isLeft()) {
          return CloudflarePublishOutcomes.verificationSuccess(
            target,
            localStateSaved: committed.isRight(),
          );
        }
      } else if (verificationOnly) {
        return CloudflarePublishOutcomes.verificationSuccess(
          target,
          localStateSaved: true,
        );
      }
    } else if (verificationOnly) {
      return const PublishFailure(
        CloudflareErrorMessages.publicationVerificationFailed,
      );
    }

    final replacing = initial.requiresReplacement;
    if (confirmation != null && !replacing) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }
    if (replacing || confirmation != null) {
      inputs = await replacement.readInputs(
        reads: _reads,
        target: target,
        section: section,
        complete: true,
        existing: inputs,
      );
      if (inputs == null) return const PublishFailure(_readFailed);
    }

    PublishSnapshot snapshot;
    if (replacing) {
      final prepared = await replacement.prepare(
        target: target,
        requestedSection: section,
        inputs: inputs,
      );
      final failure = prepared.swap().toNullable();
      if (failure != null) return CloudflarePublishOutcomes.failure(failure);
      final complete = prepared.toNullable()!;
      if (confirmation == null ||
          complete.summary.digest != confirmation.digest) {
        return PublishReplacementRequired(complete.summary);
      }
      snapshot = complete.snapshot;
    } else {
      if (section == PublishRequestedSection.events &&
          local.entryFor(CatalogueSectionBuilder.indexHtmlPath) == null) {
        return const PublishFailure(CloudflareErrorMessages.catalogueFirst);
      }
      final built = await snapshotBuilder.build(
        inputs: inputs,
        previous: local,
        now: _clock(),
        mode: PublishMode.incremental,
      );
      final failure = built.swap().toNullable();
      if (failure != null) return CloudflarePublishOutcomes.failure(failure);
      snapshot = built.toNullable()!;
    }

    final artifacts =
        await CloudflarePublishArtifactAssembler(
          store: store,
          codec: _markerCodec,
        ).assembleLive(
          target: target,
          previous: replacing ? CloudflareSiteManifest.empty : local,
          snapshot: snapshot,
          publishId: _publishId(),
          publishedAt: _clock(),
          onlySection: replacing
              ? null
              : section == PublishRequestedSection.catalogue
              ? SiteSection.catalogue
              : SiteSection.events,
        );
    final artifactFailure = artifacts.swap().toNullable();
    if (artifactFailure != null) {
      if (artifactFailure is CloudflareFailure &&
          artifactFailure.requiresCompleteSnapshot &&
          !replacing) {
        return replacement.prepareResult(
          reads: _reads,
          target: target,
          requestedSection: section,
          inputs: inputs,
        );
      }
      return CloudflarePublishOutcomes.failure(artifactFailure);
    }
    final publication = artifacts.toNullable()!;

    if (initial.workerExists) {
      final route = initial.route;
      if (route == null) {
        return const PublishFailure(CloudflareErrorMessages.artifactInvalid);
      }
      if (route.previewsEnabled) {
        final updated = await _deployApi.updateWorkerRoute(
          token: connection.useToken((token) => token),
          accountId: target.accountId,
          workerName: target.workerName,
          enabled: route.enabled,
          previewsEnabled: false,
        );
        if (updated.previewsEnabled) {
          return const PublishFailure(
            CloudflareErrorMessages.versionUrlPrivacy,
          );
        }
      }
    }

    final uploadedPaths = <String>[];
    final session = await _deployApi.createUploadSession(
      token: connection.useToken((token) => token),
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: publication.uploadManifest,
    );
    var completion = session.completionTokenWhenDeduplicated;
    for (final bucket in session.buckets) {
      final assets = <CloudflareBucketAsset>[];
      for (final hash in bucket) {
        final asset = publication.assetForHash(hash);
        if (asset == null) {
          if (!replacing) {
            return replacement.prepareResult(
              reads: _reads,
              target: target,
              requestedSection: section,
              inputs: inputs,
            );
          }
          return PublishFailure(
            '${CloudflareErrorMessages.missingRequestedHash} '
            '${progress.assetBytesNote}',
          );
        }
        assets.add(asset);
      }
      progress.assetBytesMayHaveUploaded = true;
      completion = await _deployApi.uploadBucket(
        accountId: target.accountId,
        session: session,
        assets: assets,
      );
      for (final hash in bucket) {
        uploadedPaths.addAll(publication.pathsForHash(hash));
      }
    }
    final completionToken = completion;
    if (completionToken == null) {
      return const PublishFailure(CloudflareErrorMessages.artifactInvalid);
    }

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
      final route = await _deployApi.updateWorkerRoute(
        token: connection.useToken((token) => token),
        accountId: target.accountId,
        workerName: target.workerName,
        enabled: true,
        previewsEnabled: false,
      );
      if (!route.enabled || route.previewsEnabled) {
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
      availabilityOmitted: snapshot.availabilityOmitted,
      pagesLive: verified == CloudflarePublicationVerification.verified
          ? true
          : null,
      localStateSaved: localStateSaved,
    );
  }

  static const String _readFailed = PublishSnapshotBuilder.readFailedMessage;
}
