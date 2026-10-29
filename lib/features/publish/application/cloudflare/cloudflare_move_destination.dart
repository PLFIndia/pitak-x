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
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_snapshot_preparation.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
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
      if (initial.toNullable()!.freshness == PublishFreshness.siteUnavailable) {
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.siteUnavailable),
        );
      }
      final prepared = await _preparation(store)(
        reads: _reads,
        oldTarget: oldTarget,
        newTarget: newTarget,
        sourceAnchor: sourceAnchor,
      );
      if (prepared case Left(value: final failure)) return Left(failure);
      return Right(prepared.toNullable()!.confirmation);
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
  }) async {
    final target = confirmation.newTarget;
    if (target is! CloudflarePublishTarget) {
      return const MoveDestinationFailed(MoveSiteMessages.targetMismatch);
    }
    final store = _artifactStores();
    MoveDestinationResult result;
    try {
      result = await _publish(confirmation, target, store, beforeWrite);
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
    if (initial.freshness == PublishFreshness.siteUnavailable) {
      return const MoveDestinationFailed(
        CloudflareErrorMessages.siteUnavailable,
      );
    }

    if (initial.freshness == PublishFreshness.known &&
        _matchesSnapshot(current.local, complete.snapshot)) {
      return _verifyExisting(current, target);
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
    if (existingRoute?.previewsEnabled ?? false) {
      final route = await _deployApi.updateWorkerRoute(
        token: token,
        accountId: target.accountId,
        workerName: target.workerName,
        enabled: existingRoute!.enabled,
        previewsEnabled: false,
      );
      if (route.previewsEnabled) {
        return const MoveDestinationFailed(
          CloudflareErrorMessages.versionUrlPrivacy,
        );
      }
    }

    final session = await _deployApi.createUploadSession(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: publication.uploadManifest,
    );
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
    if (!initial.hasSameAnchor(last) || !await beforeWrite()) {
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
    return _saveDeployedAndVerify(current, target, publication);
  }

  Future<MoveDestinationResult> _saveDeployedAndVerify(
    CloudflareMoveConnection current,
    CloudflarePublishTarget target,
    CloudflarePublicationArtifacts publication,
  ) async {
    _manifest.save(publication.manifest);
    final token = current.connection.useToken((value) => value);
    final route = await _deployApi.updateWorkerRoute(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      enabled: true,
      previewsEnabled: false,
    );
    if (!route.enabled || route.previewsEnabled) {
      return const MoveDestinationFailed(
        CloudflareErrorMessages.versionUrlPrivacy,
      );
    }
    final verified = await _verifier.verify(
      target: target,
      manifest: publication.manifest,
      markerBytes: publication.markerBytes,
      revision: _clock(),
    );
    if (verified != CloudflarePublicationVerification.verified) {
      return const MoveDestinationFailed(
        MoveSiteMessages.destinationNotVerified,
      );
    }
    final saved = (await _verifiedCommit.call(
      connection: current.connection,
      target: target,
      manifest: publication.manifest,
    )).isRight();
    return MoveDestinationPublished(localStateSaved: saved);
  }

  Future<MoveDestinationResult> _verifyExisting(
    CloudflareMoveConnection current,
    CloudflarePublishTarget target,
  ) async {
    final verified = await _verifier.verify(
      target: target,
      manifest: current.local,
      revision: _clock(),
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
