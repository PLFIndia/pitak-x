/// Complete Cloudflare destination publication for S9 moves.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_preparation.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_reader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_session_baseline.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_version_url_gate.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_snapshot_preparation.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// Publishes a strict complete Worker snapshot, or recovers its existing one.
final class CloudflareMoveDestination implements MoveDestinationPublisher {
  /// Creates destination operations over ordinary Cloudflare building blocks.
  const CloudflareMoveDestination({
    required CloudflareMoveReader reader,
    required CloudflareDeployApi deployApi,
    required CloudflareManifestStore manifest,
    required PublishSnapshotBuilder snapshotBuilder,
    required PublishReads reads,
    required CloudflareArtifactStoreFactory artifactStores,
    required PublishMarkerCodec markerCodec,
    required CloudflarePublishMarkerProbe markerProbe,
    required CloudflarePublicationVerifier verifier,
    required CloudflareVerifiedStateCommit verifiedCommit,
    required int Function() clock,
    String Function()? publishId,
  }) : _reader = reader,
       _deployApi = deployApi,
       _manifest = manifest,
       _snapshotBuilder = snapshotBuilder,
       _reads = reads,
       _artifactStores = artifactStores,
       _markerCodec = markerCodec,
       _markerProbe = markerProbe,
       _verifier = verifier,
       _verifiedCommit = verifiedCommit,
       _clock = clock,
       _publishId = publishId ?? PublishMarker.generatePublishId;

  final CloudflareMoveReader _reader;
  final CloudflareDeployApi _deployApi;
  final CloudflareManifestStore _manifest;
  final PublishSnapshotBuilder _snapshotBuilder;
  final PublishReads _reads;
  final CloudflareArtifactStoreFactory _artifactStores;
  final PublishMarkerCodec _markerCodec;
  final CloudflarePublishMarkerProbe _markerProbe;
  final CloudflarePublicationVerifier _verifier;
  final CloudflareVerifiedStateCommit _verifiedCommit;
  final int Function() _clock;
  final String Function() _publishId;

  @override
  Future<Either<Failure, MoveSiteConfirmation>> prepare({
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
  }) async {
    if (newTarget is! CloudflarePublishTarget) return _mismatch();
    final store = _artifactStores();
    try {
      final current = await _reader.connection(newTarget);
      if (current case Left(value: final failure)) return Left(failure);
      final initial = await _reader.check(
        current.toNullable()!,
        newTarget,
        'move-prepare-${_clock()}',
      );
      if (initial case Left(value: final failure)) return Left(failure);
      final reviewed = initial.toNullable()!;
      final prepared = await _preparation(store)(
        reads: _reads,
        oldTarget: oldTarget,
        newTarget: newTarget,
        sourceAnchor: sourceAnchor,
      );
      if (prepared case Left(value: final failure)) return Left(failure);
      final confirmation = prepared.toNullable()!.confirmation;
      // N2: a deleted Worker is recreated by this complete snapshot. The
      // review says so instead of refusing the move forever.
      return Right(
        reviewed.freshness == PublishFreshness.siteUnavailable
            ? confirmation.withDestinationWarning(
                MoveSiteMessages.workerMissingDestination(newTarget.siteUrl),
              )
            : confirmation,
      );
    } on Exception {
      return const Left(CloudflareFailure(CloudflareErrorMessages.generic));
    } finally {
      await store.dispose();
    }
  }

  MoveSnapshotPreparation _preparation(CloudflareArtifactStore store) =>
      cloudflareMovePreparation(
        builder: _snapshotBuilder,
        store: store,
        clock: _clock,
      );

  @override
  Future<MoveDestinationResult> publish({
    required MoveSiteConfirmation confirmation,
    required Future<bool> Function() beforeWrite,
    MoveVerificationProgress? onVerify,
  }) async {
    final target = confirmation.newTarget;
    if (target is! CloudflarePublishTarget) {
      return const MoveDestinationFailed(MoveSiteMessages.targetMismatch);
    }
    final store = _artifactStores();
    MoveDestinationResult result;
    try {
      result = await _publish(
        confirmation,
        target,
        store,
        beforeWrite,
        onVerify,
      );
    } on CloudflareApiException catch (error) {
      result = MoveDestinationFailed(
        CloudflareErrorMessages.forFailure(
          CloudflareErrorMessages.fromException(error),
        ),
      );
    } on Exception {
      result = const MoveDestinationFailed(MoveSiteMessages.generic);
    }
    final cleanup = await store.dispose();
    if (cleanup.isLeft() && result is MoveDestinationPublished) {
      return const MoveDestinationPublished(temporaryCleanupFailed: true);
    }
    return result;
  }

  Future<MoveDestinationResult> _publish(
    MoveSiteConfirmation confirmation,
    CloudflarePublishTarget target,
    CloudflareArtifactStore store,
    Future<bool> Function() beforeWrite,
    MoveVerificationProgress? onVerify,
  ) async {
    final prepared = await _preparation(store)(
      reads: _reads,
      oldTarget: confirmation.oldTarget,
      newTarget: target,
      sourceAnchor: confirmation.sourceAnchor,
    );
    final prepareFailure = prepared.swap().toNullable();
    if (prepareFailure != null) {
      return MoveDestinationFailed(_message(prepareFailure));
    }
    final complete = prepared.toNullable()!;
    if (complete.confirmation.digest != confirmation.digest) {
      return MoveDestinationConfirmationRequired(complete.confirmation);
    }
    final connected = await _reader.connection(target);
    final connectionFailure = connected.swap().toNullable();
    if (connectionFailure != null) {
      return MoveDestinationFailed(_message(connectionFailure));
    }
    final current = connected.toNullable()!;
    final initialResult = await _reader.check(
      current,
      target,
      'move-initial-${_clock()}',
    );
    final initialFailure = initialResult.swap().toNullable();
    if (initialFailure != null) {
      return MoveDestinationFailed(_message(initialFailure));
    }
    final initial = initialResult.toNullable()!;

    if (initial.freshness == PublishFreshness.known &&
        _matchesSnapshot(current.local, complete.snapshot)) {
      return _verifyExisting(
        current,
        target,
        route: initial.route,
        onVerify: onVerify,
      );
    }
    final artifacts =
        await CloudflarePublishArtifactAssembler(
          store: store,
          codec: _markerCodec,
        ).assembleLive(
          target: target,
          previous: CloudflareSiteManifest.empty,
          snapshot: complete.snapshot,
          publishId: _publishId(),
          publishedAt: _clock(),
        );
    final artifactFailure = artifacts.swap().toNullable();
    if (artifactFailure != null) {
      return MoveDestinationFailed(_message(artifactFailure));
    }
    final publication = artifacts.toNullable()!;
    final token = current.connection.useToken((value) => value);
    final existingRoute = initial.route;
    if (initial.workerExists && existingRoute == null) {
      return const MoveDestinationFailed(
        MoveSiteMessages.destinationNotVerified,
      );
    }
    if (existingRoute != null) {
      final private = await CloudflareVersionUrlGate(deployApi: _deployApi)
          .ensureOff(
            token: token,
            accountId: target.accountId,
            workerName: target.workerName,
            route: existingRoute,
          );
      if (!private) {
        return const MoveDestinationFailed(
          CloudflareErrorMessages.versionUrlPrivacy,
        );
      }
    }

    // RH1, the same rule as an ordinary publish: a Worker that appeared
    // BEFORE our session is someone else's; one our session creates is ours.
    if (await CloudflareSessionBaseline.workerAppeared(
      sawWorkerInitially: initial.workerExists,
      workerExists: () => _deployApi.workerExists(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
      ),
    )) {
      return const MoveDestinationFailed(MoveSiteMessages.sourceChanged);
    }
    final session = await _deployApi.createUploadSession(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: publication.uploadManifest,
    );
    final baselineResult = await CloudflareSessionBaseline.afterSession(
      initial: initial,
      read: () =>
          _reader.check(current, target, 'move-post-session-${_clock()}'),
    );
    final baselineFailure = baselineResult.swap().toNullable();
    if (baselineFailure != null) {
      return MoveDestinationFailed(_message(baselineFailure));
    }
    final baseline = baselineResult.toNullable()!;
    final upload = await CloudflareBucketUploader(_deployApi).upload(
      accountId: target.accountId,
      session: session,
      assetForHash: publication.assetForHash,
    );
    final CloudflareCompletionToken completion;
    switch (upload) {
      case CloudflareBucketsUploaded():
        completion = upload.completion;
      case CloudflareBucketHashMissing():
        return const MoveDestinationFailed(
          CloudflareErrorMessages.missingRequestedHash,
        );
      case CloudflareUploadNotConfirmed():
        return const MoveDestinationFailed(
          CloudflareErrorMessages.uploadNotConfirmed,
        );
    }
    final lastResult = await _reader.check(
      current,
      target,
      'move-final-${_clock()}',
    );
    final lastFailure = lastResult.swap().toNullable();
    if (lastFailure != null) {
      return MoveDestinationFailed(_message(lastFailure));
    }
    final last = lastResult.toNullable()!;
    // N5: the destination moved, or the source moved. Naming the wrong site
    // sent the user to fix a site that had not changed.
    if (!baseline.hasSameAnchor(last)) {
      return const MoveDestinationFailed(MoveSiteMessages.destinationChanged);
    }
    if (!await beforeWrite()) {
      return const MoveDestinationFailed(MoveSiteMessages.sourceChanged);
    }
    await _deployApi.deploy(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      completionToken: completion,
      kind: CloudflareDeploymentKind.live,
      recovery: () => _markerProbe.recoverLiveDeployment(
        target: target,
        expected: publication.marker,
      ),
    );
    return _saveDeployedAndVerify(
      current,
      target,
      publication,
      onVerify: onVerify,
    );
  }

  Future<MoveDestinationResult> _saveDeployedAndVerify(
    CloudflareMoveConnection current,
    CloudflarePublishTarget target,
    CloudflarePublicationArtifacts publication, {
    MoveVerificationProgress? onVerify,
  }) async {
    // L12: this record is what proves the deploy was ours, so its save result
    // must reach the user instead of being discarded.
    final recordSaved = _manifest.save(publication.manifest).isRight();
    final localNote = recordSaved
        ? ''
        : ' ${MoveSiteMessages.localRecordNotSaved}';
    final token = current.connection.useToken((value) => value);
    // N4: a route write here can throw. That must say the deploy was accepted,
    // not collapse into a generic "move could not be completed".
    bool private;
    try {
      private = await CloudflareVersionUrlGate(deployApi: _deployApi)
          .afterDeploy(
            token: token,
            accountId: target.accountId,
            workerName: target.workerName,
          );
    } on CloudflareApiException {
      private = false;
    }
    if (!private) {
      return MoveDestinationFailed(
        '${CloudflareErrorMessages.versionUrlPrivacy} '
        '${CloudflareErrorMessages.deploymentAccepted}$localNote',
        localStateSaved: recordSaved,
      );
    }
    onVerify?.call();
    final verified = await _verifier.verify(
      target: target,
      manifest: publication.manifest,
      markerBytes: publication.markerBytes,
      revision: _clock(),
    );
    if (verified != CloudflarePublicationVerification.verified) {
      return MoveDestinationFailed(
        '${MoveSiteMessages.destinationNotVerified}$localNote',
        localStateSaved: recordSaved,
      );
    }
    final saved = (await _verifiedCommit.call(
      connection: current.connection,
      target: target,
      manifest: publication.manifest,
    )).isRight();
    return MoveDestinationPublished(localStateSaved: recordSaved && saved);
  }

  Future<MoveDestinationResult> _verifyExisting(
    CloudflareMoveConnection current,
    CloudflarePublishTarget target, {
    CloudflareWorkerRoute? route,
    MoveVerificationProgress? onVerify,
  }) async {
    // L3: adopting an existing destination is still a "verified" result, so
    // it may not be reported while Version URLs are public. The route is the
    // one the preflight just read.
    try {
      final private = await CloudflareVersionUrlGate(deployApi: _deployApi)
          .ensureOff(
            token: current.connection.useToken((token) => token),
            accountId: target.accountId,
            workerName: target.workerName,
            route: route,
          );
      if (!private) {
        return const MoveDestinationFailed(
          CloudflareErrorMessages.versionUrlPrivacy,
        );
      }
    } on CloudflareApiException {
      return const MoveDestinationFailed(
        CloudflareErrorMessages.versionUrlPrivacy,
      );
    }
    onVerify?.call();
    final verified = await _verifier.verify(
      target: target,
      manifest: current.local,
      revision: _clock(),
      // An existing destination is an earlier deployment, so it gets the
      // short budget rather than the post-deploy wait (M2).
      budget: CloudflareReadBackBudget.earlierDeployment,
    );
    if (verified != CloudflarePublicationVerification.verified) {
      return const MoveDestinationFailed(
        MoveSiteMessages.destinationNotVerified,
      );
    }
    final saved = await _verifiedCommit.call(
      connection: current.connection,
      target: target,
      manifest: current.local,
    );
    return MoveDestinationPublished(localStateSaved: saved.isRight());
  }

  static bool _matchesSnapshot(
    CloudflareSiteManifest local,
    PublishSnapshot snapshot,
  ) {
    if (local.target == null || local.state == PublishState.retired) {
      return false;
    }
    final desired = <String, String>{
      for (final section in snapshot.sections)
        for (final file in section.files) file.path: file.gitSha,
    };
    final actual = <String, String>{
      for (final entry in local.files.entries)
        if (entry.key != 'pitak-publish.json') entry.key: entry.value.sha,
    };
    return actual.length == desired.length &&
        desired.entries.every((entry) => actual[entry.key] == entry.value);
  }

  static Either<Failure, Never> _mismatch() =>
      const Left(CloudflareFailure(CloudflareErrorMessages.targetMismatch));

  static String _message(Failure failure) => switch (failure) {
    PublishReadFailure(:final message) ||
    ValidationFailure(:final message) ||
    CloudflareFailure(:final message) => message,
    NetworkFailure() =>
      'The publishing service could not be reached. Try again.',
    _ => MoveSiteMessages.generic,
  };
}
