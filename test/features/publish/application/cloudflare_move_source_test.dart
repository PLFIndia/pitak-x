import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_reader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_source.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/site/move_site_operations.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

import '../support/cloudflare_fakes.dart';
import '../support/cloudflare_s8_fakes.dart';
import '../support/move_fakes.dart';

const _codec = CloudflarePublishMarkerCodec();

void main() {
  late Directory dir;
  late FakeCloudflareApi api;
  late InMemoryCloudflareCredentialStore credentials;
  late InMemoryCloudflareManifestStore manifests;
  late FakeStructuredReader reader;
  late RecordingArtifactStore store;
  late CloudflareMoveSource source;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitak_move_cf_');
    api = FakeCloudflareApi()..workerExistsValue = true;
    credentials = InMemoryCloudflareCredentialStore(cloudflareTestConnection());
    manifests = InMemoryCloudflareManifestStore(
      s8Manifest(
        target: moveCloudflareTarget,
        publishId: moveCloudflarePublishId,
      ),
    );
    reader = FakeCloudflareWorkerReader()
      ..body(CloudflareLimits.markerPath, s8Marker(moveCloudflarePublishId));
    store = RecordingArtifactStore(
      FilePublishArtifactStore(
        spoolRoot: PublishArtifactSpoolRoot(tempRoot: dir),
      ),
    );
    final probe = CloudflarePublishMarkerProbe(reader: reader, codec: _codec);
    final moveReader = CloudflareMoveReader(
      credentials: credentials,
      manifest: manifests,
      preflight: CloudflarePublishPreflightReader(
        accountApi: api,
        deployApi: api,
        markerProbe: probe,
      ),
    );
    source = CloudflareMoveSource(
      reader: moveReader,
      deployApi: api,
      manifest: manifests,
      artifactStores: () => store,
      markerCodec: _codec,
      markerProbe: probe,
      verifier: MovedSiteVerifier(
        reader: reader,
        markerCodec: _codec,
        validateMovedHtml: (_) async => true,
        sleep: (_) async {},
        attempts: 1,
      ),
      clock: () => 1700000000000,
    );
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test(
    'readAnchor proves the exact live publication and owned paths',
    () async {
      final anchor = await source.readAnchor(moveCloudflareTarget);

      final value = anchor.getOrElse((f) => fail('expected success, got $f'));
      expect(value.value, moveCloudflarePublishId);
      expect(value.branch, isNull);
      expect(value.ownedPaths, [
        'books.json',
        'index.html',
        CloudflareLimits.markerPath,
      ]);
      expect(api.workerExistsCalls, greaterThan(0));
    },
  );

  test('readAnchor refuses a local record for another publication', () async {
    manifests.current = s8Manifest(
      target: moveCloudflareTarget,
      publishId: moveRetiredPublishId,
    );

    final anchor = await source.readAnchor(moveCloudflareTarget);

    expect(anchor.isLeft(), isTrue);
  });

  test('readAnchor refuses credential drift to another Worker', () async {
    credentials.record = cloudflareTestConnection(
      withWorker: false,
    ).selectWorker(cloudflareTestWorker('another-worker'));

    final anchor = await source.readAnchor(moveCloudflareTarget);

    final failure = anchor.swap().toNullable()!;
    expect(failure, isA<CloudflareFailure>());
    expect(api.workerExistsCalls, 0);
  });

  test('retire disables preview URLs, deploys exactly three files, verifies '
      'and saves the retired manifest', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    api.onDeploy = () {
      reader
        ..body('', pending.retirement.indexHtml)
        ..absent('books.json')
        ..body(
          CloudflareLimits.markerPath,
          s8Marker(moveRetiredPublishId, state: PublishMarkerState.retired),
        );
    };

    final result = await source.retire(pending);

    expect(result.isRight(), isTrue);
    expect(api.deployCalls, 1);
    expect(api.routeUpdates.last.previewsEnabled, isFalse);
    expect(
      api.uploadManifests.single.map((entry) => entry.path.value).toSet(),
      {'404.html', 'index.html', CloudflareLimits.markerPath},
    );
    final saved = manifests.current;
    expect(saved.state, PublishState.retired);
    expect(saved.publishId, moveRetiredPublishId);
    expect(saved.files.keys.toSet(), {
      '404.html',
      'index.html',
      CloudflareLimits.markerPath,
    });
  });

  test('retire adopts an already-retired Worker without a deploy', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    reader
      ..body('', pending.retirement.indexHtml)
      ..absent('books.json')
      ..body(
        CloudflareLimits.markerPath,
        s8Marker(moveRetiredPublishId, state: PublishMarkerState.retired),
      );

    final result = await source.retire(pending);

    expect(result.isRight(), isTrue);
    expect(api.deployCalls, 0);
    expect(
      api.uploadManifests,
      isEmpty,
      reason: 'no upload session for an already-retired Worker',
    );
    expect(manifests.current.state, PublishState.retired);
  });

  test('a changed source publication is never retired', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    manifests.current = s8Manifest(
      target: moveCloudflareTarget,
      publishId: moveRetiredPublishId,
    );

    final result = await source.retire(pending);

    final failure = result.swap().toNullable()!;
    expect(failure, isA<ValidationFailure>());
    expect(api.deployCalls, 0);
    expect(manifests.saves, isEmpty);
  });

  test('failed retirement read-back saves nothing', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    api.onDeploy = () {
      reader
        ..body('', <int>[1, 2, 3])
        ..absent('books.json');
    };

    final result = await source.retire(pending);

    final failure = result.swap().toNullable()!;
    expect(failure, isA<ValidationFailure>());
    expect(manifests.saves, isEmpty);
  });

  test(
    'a Worker whose version URLs cannot be disabled is not retired',
    () async {
      final pending = movePending(oldTarget: moveCloudflareTarget);
      final stubborn = _StubbornRouteApi(api);
      final probe = CloudflarePublishMarkerProbe(reader: reader, codec: _codec);
      final stuck = CloudflareMoveSource(
        reader: CloudflareMoveReader(
          credentials: credentials,
          manifest: manifests,
          preflight: CloudflarePublishPreflightReader(
            accountApi: api,
            deployApi: api,
            markerProbe: probe,
          ),
        ),
        deployApi: stubborn,
        manifest: manifests,
        artifactStores: () => store,
        markerCodec: _codec,
        markerProbe: probe,
        verifier: MovedSiteVerifier(
          reader: reader,
          markerCodec: _codec,
          validateMovedHtml: (_) async => true,
          sleep: (_) async {},
          attempts: 1,
        ),
        clock: () => 1700000000000,
      );

      final result = await stuck.retire(pending);

      final failure = result.swap().toNullable()!;
      expect(
        (failure as CloudflareFailure).message,
        CloudflareErrorMessages.versionUrlPrivacy,
      );
      expect(stubborn.deploys, 0);
      expect(manifests.saves, isEmpty);
    },
  );

  test('Skip is absent only when the Worker no longer exists', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);

    api.workerExistsValue = false;
    expect(await source.skipCheck(pending), isA<SourceAbsent>());

    api.workerExistsValue = true;
    expect(await source.skipCheck(pending), isA<SourcePresent>());
  });

  test('a refused token is "inaccessible", not a hidden Worker (M4)', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    api.workerExistsError = CloudflareApiException(
      CloudflareApiExceptionKind.forbidden,
    );

    final check = await source.skipCheck(pending);

    expect(check, isA<SourceInaccessible>());
  });

  test('an ambiguous 404 is a failed check, never absence (L2)', () async {
    final pending = movePending(oldTarget: moveCloudflareTarget);
    api.workerExistsError = CloudflareApiException(
      CloudflareApiExceptionKind.notFound,
    );

    expect(await source.skipCheck(pending), isA<SourceCheckFailed>());
  });

  test(
    'retirementObserved is true for a retired record or the moved page',
    () async {
      final pending = movePending(oldTarget: moveCloudflareTarget);
      expect(await source.retirementObserved(pending), isFalse);

      reader.body('', pending.retirement.indexHtml);
      expect(await source.retirementObserved(pending), isTrue);
    },
  );
}

/// A deploy API that ignores the preview-URL privacy request.
final class _StubbornRouteApi implements CloudflareDeployApi {
  _StubbornRouteApi(this._inner);

  final FakeCloudflareApi _inner;
  int deploys = 0;

  @override
  Future<CloudflareWorkerRoute> updateWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required bool enabled,
    required bool previewsEnabled,
  }) async => const CloudflareWorkerRoute(enabled: true, previewsEnabled: true);

  @override
  Future<void> deploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareCompletionToken completionToken,
    required CloudflareDeploymentKind kind,
    required CloudflareDeployRecoveryCallback recovery,
  }) async => deploys++;

  @override
  Future<CloudflareWorkerRoute> readWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _inner.readWorkerRoute(
    token: token,
    accountId: accountId,
    workerName: workerName,
  );

  @override
  Future<bool> workerExists({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _inner.workerExists(
    token: token,
    accountId: accountId,
    workerName: workerName,
  );

  @override
  Future<String?> latestDeploymentId({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _inner.latestDeploymentId(
    token: token,
    accountId: accountId,
    workerName: workerName,
  );

  @override
  Future<CloudflareUploadSession> createUploadSession({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required List<CloudflareAssetManifestEntry> manifest,
  }) => _inner.createUploadSession(
    token: token,
    accountId: accountId,
    workerName: workerName,
    manifest: manifest,
  );

  @override
  Future<CloudflareCompletionToken?> uploadBucket({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required List<CloudflareBucketAsset> assets,
  }) => _inner.uploadBucket(
    accountId: accountId,
    session: session,
    assets: assets,
  );
}
