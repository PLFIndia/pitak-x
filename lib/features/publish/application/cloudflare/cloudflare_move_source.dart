/// Source proof, complete retirement and warned Skip for Cloudflare moves.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_reader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_retirement_artifacts.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_version_url_gate.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker_codec.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// Retires only the recorded Worker and its exact expected live marker.
final class CloudflareMoveSource implements MoveSourceOperations {
  /// Creates source operations over the shared Cloudflare ports.
  const CloudflareMoveSource({
    required CloudflareMoveReader reader,
    required CloudflareDeployApi deployApi,
    required CloudflareManifestStore manifest,
    required CloudflareArtifactStoreFactory artifactStores,
    required PublishMarkerCodec markerCodec,
    required CloudflarePublishMarkerProbe markerProbe,
    required MovedSiteVerifier verifier,
    required int Function() clock,
  }) : _reader = reader,
       _deployApi = deployApi,
       _manifest = manifest,
       _artifactStores = artifactStores,
       _markerCodec = markerCodec,
       _markerProbe = markerProbe,
       _verifier = verifier,
       _clock = clock;

  final CloudflareMoveReader _reader;
  final CloudflareDeployApi _deployApi;
  final CloudflareManifestStore _manifest;
  final CloudflareArtifactStoreFactory _artifactStores;
  final PublishMarkerCodec _markerCodec;
  final CloudflarePublishMarkerProbe _markerProbe;
  final MovedSiteVerifier _verifier;
  final int Function() _clock;

  @override
  Future<Either<Failure, MoveSourceAnchor>> readAnchor(
    PublishTarget oldTarget,
  ) async {
    if (oldTarget is! CloudflarePublishTarget) return _mismatch();
    final current = await _reader.connection(oldTarget);
    if (current case Left(value: final failure)) return Left(failure);
    final connected = current.toNullable()!;
    final local = connected.local;
    if (local.state != PublishState.live ||
        local.publishId == null ||
        !local.describes(oldTarget) ||
        !CloudflareSiteManifest.isValidFileSet(
          state: local.state,
          paths: local.ownedPaths,
        )) {
      return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
    }
    final checked = await _reader.check(
      connected,
      oldTarget,
      'move-source-${_clock()}',
    );
    if (checked case Left(value: final failure)) return Left(failure);
    if (checked.toNullable()!.freshness != PublishFreshness.known) {
      return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
    }
    final anchor = MoveSourceAnchor.tryCreate(
      source: oldTarget,
      value: local.publishId!,
      ownedPaths: local.ownedPaths,
    );
    return anchor == null
        ? const Left(ValidationFailure(MoveSiteMessages.sourceChanged))
        : Right(anchor);
  }

  @override
  Future<Either<Failure, SiteRetirementOutcome>> retire(
    PendingMove pending, {
    MoveVerificationProgress? onVerify,
  }) async {
    final target = pending.oldTarget;
    final retiredMarker = pending.retirement.marker;
    if (target is! CloudflarePublishTarget || retiredMarker == null) {
      return _mismatch();
    }
    final store = _artifactStores();
    Either<Failure, SiteRetirementOutcome> result;
    try {
      result = await _retire(
        pending,
        target,
        retiredMarker,
        store,
        onVerify: onVerify,
      );
    } on CloudflareApiException catch (error) {
      result = Left(CloudflareErrorMessages.fromException(error));
    } on Exception {
      result = const Left(CloudflareFailure(CloudflareErrorMessages.generic));
    }
    final cleanup = await store.dispose();
    if (cleanup.isLeft() && result.isRight()) {
      return right(const SiteRetirementOutcome(temporaryCleanupFailed: true));
    }
    return result;
  }

  Future<Either<Failure, SiteRetirementOutcome>> _retire(
    PendingMove pending,
    CloudflarePublishTarget target,
    PublishMarker retiredMarker,
    CloudflareArtifactStore store, {
    MoveVerificationProgress? onVerify,
  }) async {
    final connectedResult = await _reader.connection(target);
    if (connectedResult case Left(value: final failure)) return Left(failure);
    final connected = connectedResult.toNullable()!;
    final artifactsResult = await CloudflareRetirementArtifacts.build(
      pending: pending,
      target: target,
      store: store,
      codec: _markerCodec,
    );
    if (artifactsResult case Left(value: final failure)) return Left(failure);
    final artifacts = artifactsResult.toNullable()!;
    final existing = await _markerProbe.call(
      target: target,
      cacheBuster: 'retire-check-${_clock()}',
    );
    if (!_isExactRetirement(existing, retiredMarker)) {
      final local = connected.local;
      if (local.state != PublishState.live ||
          local.publishId != pending.sourceAnchor.value) {
        return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
      }
      final initialResult = await _reader.check(
        connected,
        target,
        'retire-initial-${_clock()}',
      );
      if (initialResult case Left(value: final failure)) return Left(failure);
      final initial = initialResult.toNullable()!;
      if (initial.freshness != PublishFreshness.known) {
        return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
      }
      final token = connected.connection.useToken((value) => value);
      final route = initial.route;
      if (route == null) {
        return const Left(
          ValidationFailure(MoveSiteMessages.sourceUnavailable),
        );
      }
      final private = await CloudflareVersionUrlGate(deployApi: _deployApi)
          .ensureOff(
            token: token,
            accountId: target.accountId,
            workerName: target.workerName,
            route: route,
          );
      if (!private) {
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.versionUrlPrivacy),
        );
      }
      final deployment = await _deployRetirement(
        connected,
        target,
        artifacts,
        initial,
        retiredMarker,
      );
      if (deployment case Left(value: final failure)) return Left(failure);
    } else {
      // N3: the retirement deploy landed earlier but its route update may have
      // failed. An adopted retirement still proves previews off before the
      // move may complete (ADR 0017 Decision 7).
      final private = await _ensurePreviewsOff(connected, target);
      if (!private) {
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.versionUrlPrivacy),
        );
      }
    }
    return _verifyAndSave(pending, artifacts.manifest, onVerify: onVerify);
  }

  /// Proves Version URLs off, mapping any API failure to "not proven".
  Future<bool> _ensurePreviewsOff(
    CloudflareMoveConnection connected,
    CloudflarePublishTarget target,
  ) async {
    try {
      return await CloudflareVersionUrlGate(deployApi: _deployApi).ensureOff(
        token: connected.connection.useToken((token) => token),
        accountId: target.accountId,
        workerName: target.workerName,
      );
    } on CloudflareApiException {
      return false;
    }
  }

  Future<Either<Failure, Unit>> _deployRetirement(
    CloudflareMoveConnection connected,
    CloudflarePublishTarget target,
    CloudflareRetirementArtifacts artifacts,
    CloudflarePublishPreflight initial,
    PublishMarker retiredMarker,
  ) async {
    final token = connected.connection.useToken((value) => value);
    final session = await _deployApi.createUploadSession(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      manifest: artifacts.uploadManifest,
    );
    final upload = await CloudflareBucketUploader(_deployApi).upload(
      accountId: target.accountId,
      session: session,
      assetForHash: artifacts.assetForHash,
    );
    final CloudflareCompletionToken completion;
    switch (upload) {
      case CloudflareBucketsUploaded():
        completion = upload.completion;
      case CloudflareBucketHashMissing():
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.missingRequestedHash),
        );
      case CloudflareUploadNotConfirmed():
        return const Left(
          CloudflareFailure(CloudflareErrorMessages.uploadNotConfirmed),
        );
    }
    final lastResult = await _reader.check(
      connected,
      target,
      'retire-final-${_clock()}',
    );
    if (lastResult case Left(value: final failure)) return Left(failure);
    if (!initial.hasSameAnchor(lastResult.toNullable()!)) {
      return const Left(ValidationFailure(MoveSiteMessages.sourceChanged));
    }
    await _deployApi.deploy(
      token: token,
      accountId: target.accountId,
      workerName: target.workerName,
      completionToken: completion,
      kind: CloudflareDeploymentKind.retired,
      recovery: () => _markerProbe.recoverRetirement(
        target: target,
        expected: retiredMarker,
      ),
    );
    final private = await CloudflareVersionUrlGate(deployApi: _deployApi)
        .afterDeploy(
          token: token,
          accountId: target.accountId,
          workerName: target.workerName,
        );
    if (!private) {
      return const Left(
        CloudflareFailure(CloudflareErrorMessages.versionUrlPrivacy),
      );
    }
    return right(unit);
  }

  Future<Either<Failure, SiteRetirementOutcome>> _verifyAndSave(
    PendingMove pending,
    CloudflareSiteManifest retired, {
    MoveVerificationProgress? onVerify,
  }) async {
    onVerify?.call();
    final verified = await _verifier.verify(pending, revision: _clock());
    if (!verified) {
      return const Left(ValidationFailure(MoveSiteMessages.retirementFailed));
    }
    final saved = _manifest.save(retired);
    if (saved case Left(value: final failure)) return Left(failure);
    return right(const SiteRetirementOutcome());
  }

  static bool _isExactRetirement(
    PublishMarkerProbe probe,
    PublishMarker expected,
  ) =>
      probe is MarkerPresent &&
      probe.marker.publishId == expected.publishId &&
      probe.marker.publishedAt == expected.publishedAt &&
      probe.marker.state == PublishMarkerState.retired;

  @override
  Future<SourceSkipCheck> skipCheck(PendingMove pending) async {
    final target = pending.oldTarget;
    if (target is! CloudflarePublishTarget) return const SourceCheckFailed();
    final connected = await _reader.connection(target);
    final connection = connected.toNullable();
    if (connection == null) {
      // No exact credentials for this Worker: Pitak cannot sign in, which is
      // the "finish without retiring" case (fix-plan M4).
      return SourceInaccessible(oldSiteAnswers: await _oldSiteAnswers(pending));
    }
    try {
      final exists = await connection.connection.useToken(
        (token) => _deployApi.workerExists(
          token: token,
          accountId: target.accountId,
          workerName: target.workerName,
        ),
      );
      return exists ? const SourcePresent() : const SourceAbsent();
    } on CloudflareApiException catch (error) {
      if (error.kind == CloudflareApiExceptionKind.unauthorized ||
          error.kind == CloudflareApiExceptionKind.forbidden) {
        return SourceInaccessible(
          oldSiteAnswers: await _oldSiteAnswers(pending),
        );
      }
      return const SourceCheckFailed();
    } on Exception {
      return const SourceCheckFailed();
    }
  }

  @override
  Future<bool> retirementObserved(PendingMove pending) async {
    final target = pending.oldTarget;
    if (target is! CloudflarePublishTarget) return false;
    final local = _manifest.load();
    if (local.state == PublishState.retired && local.describes(target)) {
      return true;
    }
    return _verifier.rootServesMovedPage(pending, revision: _clock());
  }

  /// Whether the old public address still serves content.
  ///
  /// A body means visitors still see the old site; a real 404 or an unreadable
  /// answer means they do not. Used only for the finish dialog's copy.
  Future<bool> _oldSiteAnswers(PendingMove pending) async =>
      await _verifier.rootServesContent(pending, revision: _clock()) ?? false;

  static Either<Failure, Never> _mismatch() =>
      const Left(CloudflareFailure(CloudflareErrorMessages.targetMismatch));
}
