/// Ordinary Cloudflare catalogue/events publishing and R4 replacement (S8/F.3).
///
/// The app-wide operation queue is ALREADY HELD by the outer controller. This
/// use case never waits for a dialog and never enqueues nested work.
/// Preparation returns a typed replacement summary without a remote write;
/// confirmation re-enters through the controller with only a safe
/// target/section/digest.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_deploy_pipeline.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_existing_publication_check.dart';
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
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

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
      // Debug builds only (appLog): which API stage failed, never secrets.
      appLog(
        CloudflarePublishOutcomes.apiFailureDiagnostic(
          error,
          progress,
          stackTrace,
        ),
      );
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

    final stored = _manifest.load();
    final previousTarget = stored.target;
    // One rule for "what does my record claim?": a record that does not
    // describe this exact target claims nothing at all (handoff §13). Treating
    // it as an error stranded the user until they cleared app data (H1).
    var local = stored.forTarget(target);

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

    // Confirmation is bound to the remote facts the user reviewed, not to a
    // freshness category (N1/M10). An equal anchor authorises the replacement
    // the user read; a changed one never writes and asks again.
    PublishReplacementReason? replacementReason;
    if (confirmation != null) {
      if (!initial.anchor.matches(confirmation.remoteAnchor)) {
        return _reviewAgain(
          initial: initial,
          confirmation: confirmation,
          target: target,
          section: section,
          inputs: inputs,
          replacement: replacement,
        );
      }
      replacementReason = confirmation.reason;
    } else {
      if (initial.freshness == PublishFreshness.known) {
        final existing =
            await CloudflareExistingPublicationCheck(
              verifier: _verifier,
              verifiedCommit: _verifiedCommit,
              clock: _clock,
            ).call(
              connection: connection,
              target: target,
              local: local,
              verificationOnly: verificationOnly,
            );
        switch (existing) {
          case CloudflareExistingPublicationFinished(:final result):
            return result;
          case CloudflareExistingPublicationContinue(local: final repaired):
            local = repaired;
          case CloudflareExistingPublicationReplace(:final reason):
            replacementReason = reason;
        }
      } else if (verificationOnly) {
        return PublishFailure(
          local.target == null
              ? CloudflareErrorMessages.nothingToVerify
              : CloudflareErrorMessages.publicationVerificationFailed,
        );
      }
    }

    if (confirmation == null && replacementReason == null) {
      // A record for another target is a change of destination, not a remote
      // state: it is reviewed on its own terms (D1). A contradiction found by
      // the read-back above already decided, so it must not be overwritten.
      replacementReason =
          _structuralReason(previousTarget, target) ??
          _stateReason(initial.freshness);
    }
    final replacing = replacementReason != null;
    if (replacing) {
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
        remoteAnchor: initial.anchor,
        reason: replacementReason,
        previousSiteUrl: previousTarget?.siteUrl,
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
          remoteAnchor: initial.anchor,
          reason: PublishReplacementReason.localBytesMissing,
          previousSiteUrl: previousTarget?.siteUrl,
        );
      }
      return CloudflarePublishOutcomes.failure(artifactFailure);
    }
    final publication = artifacts.toNullable()!;

    return CloudflareDeployPipeline(
      deployApi: _deployApi,
      manifest: _manifest,
      preflight: _preflight,
      markerProbe: _markerProbe,
      verifier: _verifier,
      verifiedCommit: _verifiedCommit,
      replacement: replacement,
      reads: _reads,
      clock: _clock,
    ).run(
      connection: connection,
      target: target,
      section: section,
      local: local,
      initial: initial,
      publication: publication,
      inputs: inputs,
      replacing: replacing,
      availabilityOmitted: snapshot.availabilityOmitted,
      progress: progress,
    );
  }

  /// The replacement reason implied by a preflighted freshness category.
  ///
  /// `known`, `newSite` and (until the recreate flow lands) `siteUnavailable`
  /// do not justify a replacement by themselves.
  static PublishReplacementReason? _stateReason(PublishFreshness freshness) =>
      switch (freshness) {
        PublishFreshness.unknown => PublishReplacementReason.unknownRemoteState,
        PublishFreshness.knownRetired => PublishReplacementReason.retiredSite,
        PublishFreshness.siteUnavailable =>
          PublishReplacementReason.workerMissing,
        _ => null,
      };

  /// The reason implied by a record that describes a different destination.
  ///
  /// `targetChanged` wins over `addressChanged`: another Worker (or account)
  /// is a new site, while the same Worker at a new address is a rebuild at the
  /// new address. Both deploy a complete snapshot because `library.json`
  /// embeds the address (D1).
  static PublishReplacementReason? _structuralReason(
    CloudflarePublishTarget? previousTarget,
    CloudflarePublishTarget target,
  ) {
    if (previousTarget == null) return null;
    if (previousTarget.targetId != target.targetId) {
      return PublishReplacementReason.targetChanged;
    }
    if (previousTarget.siteUrl != target.siteUrl) {
      return PublishReplacementReason.addressChanged;
    }
    return null;
  }

  /// A confirmed review is stale when the remote changed after it.
  ///
  /// The user reviews remote facts, so a changed anchor always needs a new
  /// review. Once the site matches this phone's own record, the confirmation
  /// itself no longer describes anything to replace: pressing Publish again is
  /// the honest next step (`stalePublish`).
  bool _stillNeedsReplacement(
    PublishFreshness freshness,
    PublishReplacementReason confirmed,
  ) {
    if (freshness != PublishFreshness.known) return true;
    return confirmed == PublishReplacementReason.localBytesMissing ||
        confirmed == PublishReplacementReason.recordContradicted;
  }

  /// Returns a fresh summary (asking again) or a stale refusal. No write.
  Future<PublishResult> _reviewAgain({
    required CloudflarePublishPreflight initial,
    required PublishReplacementSummary confirmation,
    required CloudflarePublishTarget target,
    required PublishRequestedSection section,
    required PublishInputs inputs,
    required CloudflareReplacementPreparation replacement,
  }) async {
    if (!_stillNeedsReplacement(initial.freshness, confirmation.reason)) {
      return const PublishFailure(CloudflareErrorMessages.stalePublish);
    }
    return replacement.prepareResult(
      reads: _reads,
      target: target,
      requestedSection: section,
      inputs: inputs,
      remoteAnchor: initial.anchor,
      reason: _stateReason(initial.freshness) ?? confirmation.reason,
      previousSiteUrl: confirmation.previousSiteUrl,
      remoteChangedSinceReview: true,
    );
  }

  static const String _readFailed = PublishSnapshotBuilder.readFailedMessage;
}
