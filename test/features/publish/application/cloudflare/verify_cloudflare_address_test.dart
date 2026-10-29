import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

import '../../support/cloudflare_fakes.dart';

T _right<T>(Either<Failure, T> result) => switch (result) {
  Right(value: final value) => value,
  Left(value: final failure) => fail('Expected right, got $failure'),
};

String _failureMessage(Either<Failure, Object?> result) => result.fold(
  CloudflareErrorMessages.forFailure,
  (_) => fail('Expected a failure'),
);

CloudflareSetupHarness _manualHarness() => CloudflareSetupHarness(
  connection: cloudflareTestConnection(withWorker: false, confirmed: false),
);

Future<Either<Failure, CloudflareWorkerOutcome>> _verify(
  CloudflareSetupHarness h, {
  bool exists = false,
  bool consent = false,
}) {
  h.api.workerExistsValue = exists;
  h.verifier.body = cloudflareTestMarkerBytes();
  return h.setup.selectWorker(
    'pitak-library',
    replacementConsent: consent,
    verificationConfirmed: true,
  );
}

void main() {
  test(
    'new Worker deploys only a verification marker and confirms target',
    () async {
      final h = _manualHarness();
      final ready = _right(await _verify(h)) as CloudflareWorkerReady;

      expect(
        ready.target.siteUrl,
        'https://pitak-library.library.workers.dev/',
      );
      expect(ready.workersWriteConfirmed, isTrue);
      expect(h.api.deployCalls, 1);
      expect(h.api.bucketCalls, 0, reason: 'empty buckets use the session JWT');
      expect(h.api.uploadManifests, hasLength(1));
      expect(h.api.uploadManifests.single, hasLength(1));
      expect(
        h.api.uploadManifests.single.single.path.value,
        CloudflareLimits.markerPath,
      );
      expect(h.api.routeUpdates, hasLength(1));
      expect(h.api.routeUpdates.single.enabled, isTrue);
      expect(h.api.routeUpdates.single.previewsEnabled, isFalse);
      expect(h.verifier.calls.last.siteUrl, ready.target.siteUrl);
      expect(h.verifier.calls.last.path, CloudflareLimits.markerPath);
      expect(
        h.credentials.record?.status.target?.targetId,
        ready.target.targetId,
      );
      expect(h.hostStore.stored?.activeHost, PublishHost.cloudflare);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
    },
  );

  test(
    'existing Worker gets pre/post version gates after explicit consent',
    () async {
      final h = _manualHarness();
      h.api.route = const CloudflareWorkerRoute(
        enabled: false,
        previewsEnabled: true,
      );

      final refused = await _verify(h, exists: true);
      expect(_right(refused), isA<CloudflareWorkerReplacementRequired>());
      expect(h.api.deployCalls, 0);
      expect(h.api.uploadManifests, isEmpty);

      _right(await _verify(h, exists: true, consent: true));
      expect(h.api.routeReadCalls, 1);
      expect(h.api.routeUpdates, hasLength(2));
      expect(h.api.routeUpdates.first.enabled, isFalse);
      expect(h.api.routeUpdates.first.previewsEnabled, isFalse);
      expect(h.api.routeUpdates.last.enabled, isTrue);
      expect(h.api.routeUpdates.last.previewsEnabled, isFalse);
      expect(h.api.deployCalls, 1);
    },
  );

  test('a requested marker bucket uploads before deployment', () async {
    final h = _manualHarness();
    final bytes = cloudflareTestMarkerBytes();
    final path = SitePath.tryParse(CloudflareLimits.markerPath)!;
    final hash = CloudflareAssetHash.forPath(bytes, path)!;
    h.api.uploadSession = CloudflareUploadSession.tryCreate(
      uploadJwt: 'synthetic-upload-jwt',
      buckets: [
        [hash],
      ],
    )!;

    _right(await _verify(h));
    expect(h.api.bucketCalls, 1);
    expect(h.api.deployCalls, 1);
  });

  test('a final bucket without a completion token never deploys', () async {
    final h = _manualHarness();
    final bytes = cloudflareTestMarkerBytes();
    final path = SitePath.tryParse(CloudflareLimits.markerPath)!;
    final hash = CloudflareAssetHash.forPath(bytes, path)!;
    h.api
      ..uploadSession = CloudflareUploadSession.tryCreate(
        uploadJwt: 'synthetic-upload-jwt',
        buckets: [
          [hash],
        ],
      )!
      ..issueCompletionToken = false;

    final result = await _verify(h);

    expect(result.isLeft(), isTrue);
    expect(
      _failureMessage(result),
      contains(CloudflareErrorMessages.uploadNotConfirmed),
    );
    expect(h.api.bucketCalls, 1);
    expect(h.api.deployCalls, 0);
    expect(h.credentials.record?.status.target, isNull);
  });

  test(
    'failed exact read-back leaves an unconfirmed candidate and no host switch',
    () async {
      final h = _manualHarness();
      h.api.workerExistsValue = false;
      h.verifier.body = null;
      final result = await h.setup.selectWorker(
        'pitak-library',
        verificationConfirmed: true,
      );

      expect(result.isLeft(), isTrue);
      expect(_failureMessage(result), contains('may remain on the Worker'));
      expect(
        _failureMessage(result),
        contains('other active site was not changed'),
      );
      expect(h.api.deployCalls, 1);
      expect(h.credentials.record?.status.target, isNull);
      expect(h.credentials.record?.status.unverifiedAddress, isNotNull);
      expect(h.credentials.record?.status.workersWriteConfirmed, isFalse);
      expect(h.hostStore.stored, isNull);
    },
  );

  test('wrong marker bytes are not address proof', () async {
    final h = _manualHarness();
    h.verifier.body = utf8.encode('{}');
    final result = await h.setup.selectWorker(
      'pitak-library',
      verificationConfirmed: true,
    );
    expect(result.isLeft(), isTrue);
    expect(_failureMessage(result), contains('may remain on the Worker'));
    expect(h.credentials.record?.status.target, isNull);
  });

  test('deploy recovery accepts only the exact verification marker', () async {
    final h = _manualHarness();
    _right(await _verify(h));
    final recovery = h.api.deployRecovery!;

    h.verifier.body = cloudflareTestMarkerBytes();
    expect(await recovery(), CloudflareDeployRecovery.alreadyDeployed);
    h.verifier.body = utf8.encode('{}');
    expect(await recovery(), CloudflareDeployRecovery.abort);
    h.verifier.body = null;
    expect(await recovery(), CloudflareDeployRecovery.abort);
  });

  test('existing-Worker pre-gate failure prevents upload and deploy', () async {
    final h = _manualHarness();
    h.api.routeError = CloudflareApiException(
      CloudflareApiExceptionKind.forbidden,
    );
    final result = await _verify(h, exists: true, consent: true);

    expect(result.isLeft(), isTrue);
    expect(h.api.deployCalls, 0);
    expect(h.api.uploadManifests, isEmpty);
    expect(h.credentials.record?.status.target, isNull);
  });

  test(
    'post-deploy route failure is a partial outcome, never confirmation',
    () async {
      final h = _manualHarness();
      h.api.routeError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
      final result = await _verify(h);

      expect(result.isLeft(), isTrue);
      expect(
        _failureMessage(result),
        contains(CloudflareErrorMessages.versionUrlPrivacy),
      );
      expect(_failureMessage(result), contains('may remain on the Worker'));
      expect(h.api.deployCalls, 1);
      expect(h.credentials.record?.status.target, isNull);
      expect(h.hostStore.stored, isNull);
    },
  );

  test(
    'remote verification plus local save failure is reported truthfully',
    () async {
      final h = _manualHarness();
      h.api.onDeploy = () => h.credentials.failSave = true;
      final result = await _verify(h);

      expect(result.isLeft(), isTrue);
      expect(
        _failureMessage(result),
        CloudflareErrorMessages.remoteVerifiedLocalSaveFailed,
      );
      expect(h.api.deployCalls, 1);
      expect(h.credentials.record?.status.target, isNull);
    },
  );

  test('journal failure retries finalization WITHOUT another deploy', () async {
    final h = _manualHarness()..hostStore.failSave = true;
    final first = await _verify(h);

    expect(first.isLeft(), isTrue);
    expect(_failureMessage(first), CloudflareErrorMessages.hostActivation);
    expect(h.api.deployCalls, 1);
    expect(h.credentials.record?.status.target, isNotNull);
    expect(h.credentials.record?.status.workersWriteConfirmed, isTrue);

    h.hostStore.failSave = false;
    final ready = _right(await h.setup.finishSetup()) as CloudflareWorkerReady;
    expect(ready.target, isNotNull);
    expect(h.api.deployCalls, 1);
    expect(h.hostStore.stored?.activeHost, PublishHost.cloudflare);
    expect(h.hostStore.stored?.verifiedTarget, isNull);
  });
}
