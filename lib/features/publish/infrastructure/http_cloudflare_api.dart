/// Thin aggregate facade over the Cloudflare account and deploy role adapters.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/http_cloudflare_account_api.dart';
import 'package:pitaka/features/publish/infrastructure/http_cloudflare_deploy_api.dart';

/// Production [CloudflareApi]: one transport, two role files, no secret fields.
final class HttpCloudflareApi implements CloudflareApi {
  /// Creates the fixed-origin production facade.
  HttpCloudflareApi({
    http.Client? client,
    Future<void> Function(Duration delay)? sleep,
  }) : this.withTransport(
         CloudflareHttpTransport(client: client, sleep: sleep),
       );

  /// Creates a facade over an injected transport (tests and composition root).
  HttpCloudflareApi.withTransport(CloudflareHttpTransport transport)
    : _transport = transport,
      _account = HttpCloudflareAccountApi(transport),
      _deploy = HttpCloudflareDeployApi(transport);

  final CloudflareHttpTransport _transport;
  final HttpCloudflareAccountApi _account;
  final HttpCloudflareDeployApi _deploy;

  /// Releases connections. The provider owns this exact lifecycle.
  void close() => _transport.close();

  @override
  Future<CloudflareTokenVerification> verifyUserToken(
    CloudflareApiToken token,
  ) => _account.verifyUserToken(token);

  @override
  Future<CloudflareTokenVerification> verifyAccountToken({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) => _account.verifyAccountToken(token: token, accountId: accountId);

  @override
  Future<CloudflareAccountListing> listAccounts(CloudflareApiToken token) =>
      _account.listAccounts(token);

  @override
  Future<CloudflareSubdomain?> readAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) => _account.readAccountSubdomain(token: token, accountId: accountId);

  @override
  Future<CloudflareSubdomainCheckResult> checkAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) => _account.checkAccountSubdomain(
    token: token,
    accountId: accountId,
    candidate: candidate,
  );

  @override
  Future<CloudflareSubdomain> createAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) => _account.createAccountSubdomain(
    token: token,
    accountId: accountId,
    candidate: candidate,
  );

  @override
  Future<bool> workerExists({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _deploy.workerExists(
    token: token,
    accountId: accountId,
    workerName: workerName,
  );

  @override
  Future<String?> latestDeploymentId({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _deploy.latestDeploymentId(
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
  }) => _deploy.createUploadSession(
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
  }) => _deploy.uploadBucket(
    accountId: accountId,
    session: session,
    assets: assets,
  );

  @override
  Future<void> deploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareCompletionToken completionToken,
    required CloudflareDeploymentKind kind,
    required CloudflareDeployRecoveryCallback recovery,
  }) => _deploy.deploy(
    token: token,
    accountId: accountId,
    workerName: workerName,
    completionToken: completionToken,
    kind: kind,
    recovery: recovery,
  );

  @override
  Future<CloudflareWorkerRoute> readWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) => _deploy.readWorkerRoute(
    token: token,
    accountId: accountId,
    workerName: workerName,
  );

  @override
  Future<CloudflareWorkerRoute> updateWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required bool enabled,
    required bool previewsEnabled,
  }) => _deploy.updateWorkerRoute(
    token: token,
    accountId: accountId,
    workerName: workerName,
    enabled: enabled,
    previewsEnabled: previewsEnabled,
  );
}
