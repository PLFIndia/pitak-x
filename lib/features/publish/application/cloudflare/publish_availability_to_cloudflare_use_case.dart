/// Publishes ONLY `availability.json` to a Cloudflare Worker (application
/// layer; ADR 0019 Decisions 7 and 11, plan AV10/AV13/C.6).
///
/// This is the Cloudflare half of the availability lane: after a loan, the
/// lane (plan S6) hands it a saved "not available" set, or a removal when the
/// switch is off, and this use case deploys a new Worker version that changes
/// that one file. It reads no loans, builds no catalogue and touches no
/// cover. Every other file of the site is carried by the hash this phone
/// recorded, so Cloudflare is sent exactly two files: `availability.json`
/// and the fresh marker.
///
/// One blessed way (plan G2): it is its own small use case, like the GitHub
/// availability publish, but every step that touches the site is SHARED with
/// the ordinary catalogue/events publish — the start (connection, target,
/// preflight, L4 promotion), the existing-publication check, the artifact
/// assembler and the deploy pipeline with every gate it runs. Only the
/// decisions that are the lane's own live here.
///
/// Pipeline:
///  1. the connection for exactly this target, the record, the read-only
///     preflight and the L4 promotion ([CloudflarePublishStarter]);
///  2. a removal deletes only a RECORDED file (R13): with none recorded there
///     is nothing of ours to delete, whatever the site holds;
///  3. gate 7b, the record half (writes only): the recorded `books.json`
///     carries this phone's keys (`catalogueKeyed`); otherwise "not ready";
///  4. the live marker is this phone's own (freshness `known`). For a write
///     that is the marker half of gate 7b. A removal needs it too, for a
///     different reason: every Cloudflare deploy is a COMPLETE version built
///     from this phone's record, so deploying over a site this phone did not
///     publish last would be a whole-site replacement nobody reviewed;
///  5. the existing-publication check proves an unproven earlier deploy, and
///     a contradiction stops here;
///  6. build the section; if it changes nothing, deploy nothing;
///  7. assemble the availability-only version and run the deploy pipeline,
///     with the availability-only read-back (first round at once, AV13).
///
/// **The lane never replaces a site** (ADR 0019 Decision 11, plan G6): a
/// foreign, unknown or retired marker, a missing Worker, a contradicted
/// record and missing bytes all become "pending: Open Publish to web to
/// repair the site". The replacement preparation is not even a dependency of
/// this class, so it cannot be called.
///
/// Gates (a) "an active, connected host with a resolved target" and (c) "an
/// ordinary publish would be allowed now (no pending move)" belong to the
/// caller: it resolves [CloudflarePublishTarget] inside the publish queue
/// through `ActivePublishTargetResolver`, exactly as the GitHub lane and the
/// catalogue and events commands do (plan A.6 #47). The app-wide operation
/// queue is ALREADY HELD by that caller; nothing here waits for a dialog.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_deploy_pipeline.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_existing_publication_check.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_start.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// Orchestrates one availability-only Cloudflare publish.
final class PublishAvailabilityToCloudflareUseCase {
  /// Creates the use case over the same ports the ordinary publish uses,
  /// minus everything that reads the library or prepares a replacement.
  const PublishAvailabilityToCloudflareUseCase({
    required CloudflareDeployApi deployApi,
    required CloudflareCredentialStore credentials,
    required CloudflareManifestStore manifest,
    required CloudflarePublishPreflightReader preflight,
    required CloudflarePublishMarkerProbe markerProbe,
    required CloudflareArtifactStoreFactory artifactStores,
    required PublishMarkerCodec markerCodec,
    required CloudflarePublicationVerifier verifier,
    required CloudflareVerifiedStateCommit verifiedCommit,
    required int Function() clock,
    String Function()? publishId,
    PublishTimingSink? timingSink,
  }) : _deployApi = deployApi,
       _credentials = credentials,
       _manifest = manifest,
       _preflight = preflight,
       _markerProbe = markerProbe,
       _artifactStores = artifactStores,
       _markerCodec = markerCodec,
       _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _clock = clock,
       _publishId = publishId ?? PublishMarker.generatePublishId,
       _timingSink = timingSink;

  final CloudflareDeployApi _deployApi;
  final CloudflareCredentialStore _credentials;
  final CloudflareManifestStore _manifest;
  final CloudflarePublishPreflightReader _preflight;
  final CloudflarePublishMarkerProbe _markerProbe;
  final CloudflareArtifactStoreFactory _artifactStores;
  final PublishMarkerCodec _markerCodec;
  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final int Function() _clock;
  final String Function() _publishId;

  /// Publish-timings sink (plan S0). Null in every normal build; only
  /// `--dart-define=publishTimings=true` supplies one (plan S8 measures the
  /// lane with it).
  final PublishTimingSink? _timingSink;

  /// Publishes [update] to [target], the EXACT destination resolved by the
  /// caller inside the publish queue.
  Future<AvailabilityPublishResult> call({
    required CloudflarePublishTarget target,
    required AvailabilityUpdate update,
  }) async {
    final store = _artifactStores();
    final progress = CloudflarePublishOperationProgress();
    // One recorder per publish; a null sink makes every mark a no-op, and
    // `finally` emits the line on failure paths too (plan S0).
    final timings = PublishTimingRecorder(
      sink: _timingSink,
      operation: 'cloudflareAvailability',
      clock: _clock,
    );
    try {
      return await _run(
        target: target,
        update: update,
        store: store,
        progress: progress,
        timings: timings,
      );
    } on Exception catch (error, stackTrace) {
      // The one thrown-error policy of every Cloudflare publish: type and
      // stage only, and the truthful "accepted / uncertain / unchanged" words.
      return AvailabilityPending(
        CloudflarePublishOutcomes.thrown(error, stackTrace, progress).reason,
      );
    } finally {
      timings.finish();
      final cleanup = await store.dispose();
      if (cleanup.isLeft()) {
        // Not a site outcome, so the lane's result stands: the leftover
        // spool holds only public files (P8), and the next operation's sweep
        // removes it (PublishArtifactSpoolRoot). Debug builds still see it.
        appLog('Cloudflare availability: temporary spool cleanup failed');
      }
    }
  }

  Future<AvailabilityPublishResult> _run({
    required CloudflarePublishTarget target,
    required AvailabilityUpdate update,
    required CloudflareArtifactStore store,
    required CloudflarePublishOperationProgress progress,
    required PublishTimingRecorder timings,
  }) async {
    final starter = CloudflarePublishStarter(
      credentials: _credentials,
      manifest: _manifest,
      preflight: _preflight,
      clock: _clock,
    );
    final connected = await starter.connectionFor(target);
    if (connected case Left(value: final failure)) return _pendingFor(failure);
    final connection = connected.toNullable()!;

    final reconcileStartedAt = timings.begin();
    final started = await starter.establish(
      connection: connection,
      target: target,
    );
    if (started case Left(value: final failure)) return _pendingFor(failure);
    final start = started.toNullable()!;
    var local = start.local;

    // Step 2: only a recorded file is ours to delete (R13).
    if (update is AvailabilityDelete &&
        AvailabilitySectionBuilder.removal(previous: local) == null) {
      return const AvailabilityAlreadyPublished();
    }
    // Step 3, gate 7b (record half, writes only): keys readers cannot match
    // would show every item as Available, the dangerous direction. An empty
    // record (no publish for this target) is never keyed.
    if (update is AvailabilityWrite && !local.catalogueKeyed) {
      return const AvailabilityNotReady(
        AvailabilityPublishMessages.catalogueNotKeyed,
      );
    }
    // Step 4: the live site must be the version this phone's record
    // describes (see the file header for why a removal needs it too).
    if (start.initial.freshness != PublishFreshness.known) {
      return const AvailabilityPending(AvailabilityPublishMessages.repairSite);
    }

    // Step 5: the shared check of an earlier deploy (and its Version-URL
    // rule). It may prove a `deployed` record live; it never deploys.
    final existing =
        await CloudflareExistingPublicationCheck(
          verifier: _verifier,
          verifiedCommit: _verifiedCommit,
          deployApi: _deployApi,
          clock: _clock,
        ).call(
          connection: connection,
          target: target,
          local: local,
          verificationOnly: false,
        );
    switch (existing) {
      case CloudflareExistingPublicationContinue(local: final checked):
        local = checked;
      case CloudflareExistingPublicationReplace():
        // The record contradicts the live site: only a reviewed replacement
        // fixes that, and the lane never starts one.
        return const AvailabilityPending(
          AvailabilityPublishMessages.repairSite,
        );
      case CloudflareExistingPublicationFinished(
        result: PublishFailure(:final reason),
      ):
        return AvailabilityPending(reason);
      case CloudflareExistingPublicationFinished():
        // Only a verification-only run finishes with a success, and the lane
        // never runs one. Fail closed: nothing was sent.
        return const AvailabilityPending(CloudflareErrorMessages.generic);
    }
    timings.end(PublishTimingStage.reconcile, reconcileStartedAt);

    // Step 6: the one availability section builder (S3), against the record.
    final section = switch (update) {
      AvailabilityWrite(:final snapshot) => AvailabilitySectionBuilder.write(
        snapshot: snapshot,
        previous: local,
      ),
      AvailabilityDelete() => AvailabilitySectionBuilder.removal(
        previous: local,
      ),
    };
    if (section == null || !section.changesSite) {
      // A deploy that changes nothing would still cost a new version and
      // about 20 API calls (plan C.6 "API budget"), so none is made.
      return const AvailabilityAlreadyPublished();
    }

    // Step 7: every other file is carried by its recorded hash, so only
    // `availability.json` (when written) and the fresh marker are spooled.
    final now = _clock();
    final artifacts =
        await CloudflarePublishArtifactAssembler(
          store: store,
          codec: _markerCodec,
        ).assembleLive(
          target: target,
          previous: local,
          snapshot: PublishSnapshot.availabilityOnly(section),
          publishId: _publishId(),
          publishedAt: now,
          onlySection: SiteSection.availability,
        );
    if (artifacts case Left(value: final failure)) {
      // A carried file without a trusted hash needs a complete snapshot,
      // which only a reviewed replacement may send (N1).
      if (failure is CloudflareFailure && failure.requiresCompleteSnapshot) {
        return const AvailabilityPending(
          AvailabilityPublishMessages.repairSite,
        );
      }
      return _pendingFor(failure);
    }

    final result =
        await CloudflareDeployPipeline(
          deployApi: _deployApi,
          manifest: _manifest,
          preflight: _preflight,
          markerProbe: _markerProbe,
          verifier: _verifier,
          verifiedCommit: _verifiedCommit,
          clock: _clock,
        ).run(
          connection: connection,
          target: target,
          local: local,
          initial: start.initial,
          publication: artifacts.toNullable()!,
          readBack: CloudflareReadBackScope.availabilityOnly,
          resultUrl: target.siteUrl,
          // Cloudflare asked for bytes this phone does not have: nothing was
          // deployed, and the fix is a reviewed replacement, never the lane.
          onLocalBytesMissing: () async =>
              const PublishFailure(AvailabilityPublishMessages.repairSite),
          availabilityOmitted: false,
          progress: progress,
          timings: timings,
        );
    return _outcomeOf(result, acceptedAt: now);
  }

  /// Maps the shared pipeline's result to the lane's outcome.
  static AvailabilityPublishResult _outcomeOf(
    PublishResult result, {
    required int acceptedAt,
  }) => switch (result) {
    PublishSuccess(pagesLive: true, :final localStateSaved) => AvailabilityLive(
      acceptedAt: acceptedAt,
      localStateSaved: localStateSaved,
    ),
    // Deployed, but the read-back ran out of budget (or saw other bytes):
    // the record stays `deployed`, and the next publish's existing-
    // publication check reads it back. Cloudflare has no deferred check.
    PublishSuccess(:final localStateSaved) => AvailabilityGoingLive(
      acceptedAt: acceptedAt,
      verification: null,
      localStateSaved: localStateSaved,
    ),
    PublishFailure(:final reason) => AvailabilityPending(reason),
    // The lane's missing-bytes policy never asks for a review; reading one
    // anyway as "repair" keeps the lane from ever acting on it.
    PublishReplacementRequired() => const AvailabilityPending(
      AvailabilityPublishMessages.repairSite,
    ),
  };

  /// A typed failure from the shared steps, as its fixed, safe sentence.
  static AvailabilityPublishResult _pendingFor(Failure failure) =>
      AvailabilityPending(CloudflarePublishOutcomes.failure(failure).reason);
}
