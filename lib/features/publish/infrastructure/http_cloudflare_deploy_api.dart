/// HTTP Worker/upload/deploy adapter for Cloudflare's deployment role.
library;

import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_multipart_request.dart';

/// Deployment-side implementation of [CloudflareDeployApi].
final class HttpCloudflareDeployApi implements CloudflareDeployApi {
  /// Creates the role adapter over the shared bounded transport.
  HttpCloudflareDeployApi(this._transport);

  final CloudflareHttpTransport _transport;

  /// One bucket in flight, including hash validation and every retry (R24).
  /// Bounding each streamed chunk while serializing the operation bounds the
  /// aggregate raw + base64 + UTF-8 + multipart payload copies by construction.
  final SerialOpQueue _bucketQueue = SerialOpQueue();

  static final RegExp _hashPattern = RegExp(r'^[0-9a-f]{32}$');

  @override
  Future<bool> workerExists({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    final response = await _get(
      token,
      _workerPath(accountId, workerName),
      statusOnly: true,
    );
    if (response.statusCode == 404) return false;
    if (response.statusCode >= 200 && response.statusCode < 300) return true;
    requireCloudflareSuccess(response);
    throw StateError('Unreachable Worker-existence state');
  }

  @override
  Future<String?> latestDeploymentId({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    final response = requireCloudflareSuccess(
      await _get(token, '${_workerPath(accountId, workerName)}/deployments'),
    );
    return parseCloudflareResponse(() {
      final result = cloudflareObject(response.result, maxEntries: 8);
      final deployments = cloudflareList(
        result['deployments'],
        maxEntries: 100,
      );
      if (deployments.isEmpty) return null;
      final latest = cloudflareObject(deployments.first);
      // Diagnostic only: no freshness, ordering, or concurrency decision uses
      // this value.
      return cloudflareString(latest['id'], maxLength: 128);
    });
  }

  @override
  Future<CloudflareUploadSession> createUploadSession({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required List<CloudflareAssetManifestEntry> manifest,
  }) async {
    final wireManifest = parseCloudflareInput(() => _wireManifest(manifest));
    final response = await token.use(
      (bearer) => _transport.send(
        path: '${_workerPath(accountId, workerName)}/assets-upload-session',
        bearer: bearer,
        requestBuilder: cloudflareJsonRequest('POST', {
          'manifest': wireManifest,
        }),
        idempotent: false,
        recover: () async {
          // Creating the first session may also create the Worker. Re-read its
          // existence before retrying, but never treat existence alone as proof
          // that the uncertain session request completed.
          await workerExists(
            token: token,
            accountId: accountId,
            workerName: workerName,
          );
          return false;
        },
      ),
    );
    if (response == null) {
      throw StateError('An upload session has no already-complete recovery');
    }
    requireCloudflareSuccess(response, uncertain: true);
    return parseCloudflareResponse(() {
      final result = cloudflareObject(response.result, maxEntries: 8);
      final rawBuckets = cloudflareList(
        result['buckets'],
        maxEntries: CloudflareLimits.maxFilesPerVersion,
      );
      final buckets = <List<String>>[
        for (final rawBucket in rawBuckets)
          cloudflareList(
            rawBucket,
            maxEntries: CloudflareLimits.maxFilesPerVersion,
          ).map((hash) => cloudflareString(hash, maxLength: 32)).toList(),
      ];
      final session = CloudflareUploadSession.tryCreate(
        uploadJwt: cloudflareString(
          result['jwt'],
          maxLength: CloudflareCompletionToken.maxLength,
        ),
        buckets: buckets,
      );
      if (session == null) throw const CloudflareJsonException();
      final knownHashes = <String>{for (final entry in manifest) entry.hash};
      for (final hash in session.buckets.expand((bucket) => bucket)) {
        // A requested hash with no local byte source stops BEFORE any deploy.
        if (!knownHashes.contains(hash)) throw const CloudflareJsonException();
      }
      return session;
    });
  }

  @override
  Future<CloudflareCompletionToken> uploadBucket({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required List<CloudflareBucketAsset> assets,
  }) => _bucketQueue.enqueue(() async {
    await parseCloudflareInputAsync(() async {
      final matchesRequestedBucket = session.buckets.any(
        (bucket) => _matchesBucket(bucket, assets),
      );
      if (assets.isEmpty || !matchesRequestedBucket) {
        throw const CloudflareJsonException();
      }
      await validateCloudflareBucketAssets(assets);
    });
    final response = await session.useUploadJwt(
      (bearer) => _transport.send(
        path: '/accounts/${accountId.value}/workers/assets/upload',
        bearer: bearer,
        queryParameters: const {'base64': 'true'},
        requestBuilder: (uri) =>
            cloudflareBucketMultipartRequest(url: uri, assets: assets),
        deadline: CloudflareLimits.uploadDeadline,
      ),
    );
    if (response == null) {
      throw StateError('An idempotent upload has no write recovery');
    }
    requireCloudflareSuccess(response);
    return parseCloudflareResponse(() {
      final result = cloudflareObject(response.result, maxEntries: 8);
      final completion = CloudflareCompletionToken.tryParse(
        cloudflareString(
          result['jwt'],
          maxLength: CloudflareCompletionToken.maxLength,
        ),
      );
      if (completion == null) throw const CloudflareJsonException();
      return completion;
    });
  });

  @override
  Future<void> deploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareCompletionToken completionToken,
    required CloudflareDeploymentKind kind,
    required CloudflareDeployRecoveryCallback recovery,
  }) async {
    final response = await token.use(
      (bearer) => _transport.send(
        path: _workerPath(accountId, workerName),
        bearer: bearer,
        requestBuilder: (uri) => cloudflareDeployMultipartRequest(
          url: uri,
          completion: completionToken,
          kind: kind,
        ),
        deadline: CloudflareLimits.uploadDeadline,
        idempotent: false,
        recover: () async => switch (await recovery()) {
          CloudflareDeployRecovery.retry => false,
          CloudflareDeployRecovery.alreadyDeployed => true,
          CloudflareDeployRecovery.abort => null,
        },
      ),
    );
    if (response == null) return; // Marker read-back proved the deploy landed.
    requireCloudflareSuccess(response, uncertain: true);
  }

  @override
  Future<CloudflareWorkerRoute> readWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    final response = requireCloudflareSuccess(
      await _get(token, '${_workerPath(accountId, workerName)}/subdomain'),
    );
    return parseCloudflareResponse(() => _routeFrom(response.result));
  }

  @override
  Future<CloudflareWorkerRoute> updateWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required bool enabled,
    required bool previewsEnabled,
  }) async {
    final response = await token.use(
      (bearer) => _transport.send(
        path: '${_workerPath(accountId, workerName)}/subdomain',
        bearer: bearer,
        requestBuilder: cloudflareJsonRequest('POST', {
          'enabled': enabled,
          'previews_enabled': previewsEnabled,
        }),
        idempotent: false,
      ),
    );
    if (response == null) {
      throw StateError('A route write has no already-complete recovery');
    }
    requireCloudflareSuccess(response, uncertain: true);
    final confirmed = await readWorkerRoute(
      token: token,
      accountId: accountId,
      workerName: workerName,
    );
    if (confirmed.enabled != enabled ||
        confirmed.previewsEnabled != previewsEnabled) {
      throw CloudflareApiException(
        CloudflareApiExceptionKind.requestRejected,
        uncertain: true,
      );
    }
    return confirmed;
  }

  Future<CloudflareHttpResponse> _get(
    CloudflareApiToken token,
    String path, {
    bool statusOnly = false,
  }) async {
    final response = await token.use(
      (bearer) => _transport.send(
        path: path,
        bearer: bearer,
        requestBuilder: cloudflareJsonRequest('GET', null),
        statusOnly: statusOnly,
      ),
    );
    if (response == null) {
      throw StateError('A read-only Cloudflare call cannot be recovered');
    }
    return response;
  }

  static bool _matchesBucket(
    List<String> bucket,
    List<CloudflareBucketAsset> assets,
  ) {
    if (bucket.length != assets.length) return false;
    for (var index = 0; index < bucket.length; index++) {
      if (bucket[index] != assets[index].hash) return false;
    }
    return true;
  }

  static Map<String, Object?> _wireManifest(
    List<CloudflareAssetManifestEntry> manifest,
  ) {
    if (manifest.isEmpty ||
        manifest.length > CloudflareLimits.maxFilesPerVersion) {
      throw const CloudflareJsonException();
    }
    final result = <String, Object?>{};
    final paths = <String>{};
    for (final entry in manifest) {
      if (!_hashPattern.hasMatch(entry.hash) ||
          entry.size < 0 ||
          entry.size > CloudflareLimits.maxFileBytes ||
          CloudflareContentType.forPath(entry.path) == null ||
          !paths.add(entry.path.value)) {
        throw const CloudflareJsonException();
      }
      // The ONE leading-slash mapping lives in this adapter (B.2/R23).
      result['/${entry.path.value}'] = {'hash': entry.hash, 'size': entry.size};
    }
    return result;
  }

  static CloudflareWorkerRoute _routeFrom(Object? raw) {
    final result = cloudflareObject(raw, maxEntries: 8);
    return CloudflareWorkerRoute(
      enabled: cloudflareBool(result['enabled']),
      previewsEnabled: cloudflareBool(result['previews_enabled']),
    );
  }

  static String _workerPath(
    CloudflareAccountId accountId,
    CloudflareWorkerName workerName,
  ) => '/accounts/${accountId.value}/workers/scripts/${workerName.value}';
}
