/// Shared, synthetic Cloudflare test doubles. No real credentials or network.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_site.dart';
import 'package:pitaka/features/publish/application/cloudflare/verify_cloudflare_address.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

/// A valid synthetic account ID used throughout the tests.
const cloudflareTestAccountId = '0123456789abcdef0123456789abcdef';

/// A deterministic valid publish ID, not a production random value.
const cloudflareTestPublishId = '00112233445566778899aabbccddeeff';

/// A fixed test clock value.
const cloudflareTestNow = 1700000000000;

/// Creates a synthetic user- or account-owned token of the requested shape.
CloudflareApiToken cloudflareTestToken({bool account = false}) =>
    CloudflareApiToken.tryParse(
      '${account ? 'cfat_' : 'cfut_'}abcdefghijklmnopqrstuvwxyz123456',
    )!;

/// Creates the older 40-character user-token shape.
CloudflareApiToken cloudflareLegacyTestToken() =>
    CloudflareApiToken.tryParse(List.filled(40, 'a').join())!;

/// The selected test account ID value object.
CloudflareAccountId cloudflareTestAccount() =>
    CloudflareAccountId.tryParse(cloudflareTestAccountId)!;

/// The test subdomain value object.
CloudflareSubdomain cloudflareTestSubdomain([String value = 'library']) =>
    CloudflareSubdomain.tryParse(value)!;

/// The test Worker name value object.
CloudflareWorkerName cloudflareTestWorker([String value = 'pitak-library']) =>
    CloudflareWorkerName.tryParse(value)!;

/// Builds a connection through its invariant-preserving transition methods.
CloudflareConnection cloudflareTestConnection({
  CloudflareApiToken? token,
  bool withAccount = true,
  bool withSubdomain = true,
  bool withWorker = true,
  bool confirmed = true,
  bool writeConfirmed = false,
}) {
  var connection = CloudflareConnection.verifiedToken(
    token ?? cloudflareTestToken(),
  );
  if (withAccount) {
    connection = connection.selectAccount(
      id: cloudflareTestAccount(),
      name: 'Library account',
    );
  }
  if (withSubdomain) {
    connection = connection.selectSubdomain(
      cloudflareTestSubdomain(),
      confirmed: confirmed,
    );
  }
  if (withWorker) {
    connection = connection.selectWorker(cloudflareTestWorker());
  }
  if (writeConfirmed) {
    connection = confirmed
        ? connection.markWorkersWriteReadBack()
        : connection.markVerificationReadBack();
  }
  return connection;
}

/// In-memory whole-record store with typed failure switches.
final class InMemoryCloudflareCredentialStore
    implements CloudflareCredentialStore {
  /// Creates an empty store or one containing [record].
  InMemoryCloudflareCredentialStore([this.record]);

  /// Current record.
  CloudflareConnection? record;
  final List<CloudflareConnection> saves = [];
  int reads = 0;
  int clears = 0;
  bool failRead = false;
  bool failSave = false;
  bool failClear = false;

  @override
  Future<Either<Failure, CloudflareConnection?>> read() async {
    reads++;
    return failRead ? left(const StorageFailure('test read')) : right(record);
  }

  @override
  Future<Either<Failure, Unit>> save(CloudflareConnection connection) async {
    if (failSave) return left(const StorageFailure('test save'));
    record = connection;
    saves.add(connection);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    clears++;
    if (failClear) return left(const StorageFailure('test clear'));
    record = null;
    return right(unit);
  }
}

/// One public-verifier call, retained for origin/cap assertions.
final class CloudflareReadCall {
  /// Creates a call record.
  const CloudflareReadCall(this.siteUrl, this.path, this.maxBytes);

  /// Requested canonical site root.
  final String siteUrl;

  /// Requested relative path.
  final String path;

  /// Enforced body cap.
  final int maxBytes;
}

/// Scriptable origin-bound verifier fake.
final class FakePublishedSiteVerifier implements PublishedSiteVerifier {
  /// Bytes returned for every read; null means not verifiable.
  List<int>? body;
  final List<CloudflareReadCall> calls = [];

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    calls.add(CloudflareReadCall(siteUrl, path, maxBytes));
    return body;
  }
}

/// In-memory host journal store.
final class FakePublishHostStateStore implements PublishHostStateStore {
  /// Creates a store, optionally with [stored].
  FakePublishHostStateStore([this.stored]);

  /// Current journal.
  PublishHostState? stored;
  int saves = 0;
  bool failSave = false;

  @override
  Either<Failure, PublishHostState?> load() => right(stored);

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    saves++;
    if (failSave) return left(const StorageFailure('test host save'));
    stored = state;
    return right(unit);
  }
}

final class _FakeManifest implements PublishManifestGateway {
  /// Creates a manifest with an optional legacy GitHub repo.
  const _FakeManifest([this.repo]);

  /// Legacy repo identity, or null for no GitHub publication.
  final String? repo;

  @override
  PublishManifest load() => PublishManifest(repo: repo);

  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

/// Fully scriptable S6 API fake. Callback counts contain no bearer strings.
final class FakeCloudflareApi implements CloudflareApi {
  /// Initializes the default happy path: one account, API-read subdomain,
  /// available candidate, new Worker, deduplicated upload, and route writes.
  FakeCloudflareApi() {
    listing = CloudflareAccountListing(
      accounts: [
        CloudflareAccount(id: cloudflareTestAccount(), name: 'Library account'),
      ],
      truncated: false,
    );
    subdomain = cloudflareTestSubdomain();
    route = const CloudflareWorkerRoute(enabled: true, previewsEnabled: true);
  }

  CloudflareTokenVerification userVerification =
      const CloudflareTokenVerification(status: 'active', expiresOn: null);
  CloudflareTokenVerification accountVerification =
      const CloudflareTokenVerification(status: 'active', expiresOn: null);
  CloudflareAccountListing? listing;
  CloudflareSubdomain? subdomain;
  CloudflareSubdomainAvailability availability =
      CloudflareSubdomainAvailability.available;
  bool workerExistsValue = false;
  CloudflareWorkerRoute route = const CloudflareWorkerRoute(
    enabled: true,
    previewsEnabled: true,
  );
  CloudflareUploadSession uploadSession = CloudflareUploadSession.tryCreate(
    uploadJwt: 'synthetic-upload-jwt',
    buckets: const [],
  )!;
  CloudflareUploadSession Function(List<CloudflareAssetManifestEntry> manifest)?
  uploadSessionFactory;
  void Function()? onCreateUploadSession;
  void Function(List<CloudflareBucketAsset> assets)? onBucketUpload;
  CloudflareCompletionToken completionToken =
      CloudflareCompletionToken.tryParse('synthetic-completion-jwt')!;

  CloudflareApiException? userVerifyError;
  CloudflareApiException? accountVerifyError;
  CloudflareApiException? listError;
  CloudflareApiException? readSubdomainError;
  CloudflareApiException? checkSubdomainError;
  CloudflareApiException? createSubdomainError;
  CloudflareApiException? workerExistsError;
  CloudflareApiException? routeError;
  CloudflareApiException? sessionError;
  CloudflareApiException? uploadError;
  CloudflareApiException? deployError;

  /// Optional gate for proving cross-command queue serialization.
  Future<void>? workerExistsGate;

  int userVerifyCalls = 0;
  int accountVerifyCalls = 0;
  int listCalls = 0;
  int subdomainReadCalls = 0;
  int subdomainCheckCalls = 0;
  int subdomainCreateCalls = 0;
  int workerExistsCalls = 0;
  int routeReadCalls = 0;
  int deployCalls = 0;
  int bucketCalls = 0;
  final List<List<CloudflareAssetManifestEntry>> uploadManifests = [];
  final List<List<CloudflareBucketAsset>> bucketUploads = [];
  final List<CloudflareWorkerRoute> routeUpdates = [];
  CloudflareDeployRecoveryCallback? deployRecovery;

  /// Optional side effect after a successful fake deploy (for crash tests).
  void Function()? onDeploy;

  @override
  Future<CloudflareTokenVerification> verifyUserToken(
    CloudflareApiToken token,
  ) async {
    userVerifyCalls++;
    final error = userVerifyError;
    if (error != null) throw error;
    return userVerification;
  }

  @override
  Future<CloudflareTokenVerification> verifyAccountToken({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) async {
    accountVerifyCalls++;
    final error = accountVerifyError;
    if (error != null) throw error;
    return accountVerification;
  }

  @override
  Future<CloudflareAccountListing> listAccounts(
    CloudflareApiToken token,
  ) async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return listing!;
  }

  @override
  Future<CloudflareSubdomain?> readAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
  }) async {
    subdomainReadCalls++;
    final error = readSubdomainError;
    if (error != null) throw error;
    return subdomain;
  }

  @override
  Future<CloudflareSubdomainCheckResult> checkAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) async {
    subdomainCheckCalls++;
    final error = checkSubdomainError;
    if (error != null) throw error;
    return CloudflareSubdomainCheckResult(
      candidate: candidate,
      availability: availability,
    );
  }

  @override
  Future<CloudflareSubdomain> createAccountSubdomain({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareSubdomain candidate,
  }) async {
    subdomainCreateCalls++;
    final error = createSubdomainError;
    if (error != null) throw error;
    return candidate;
  }

  @override
  Future<bool> workerExists({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    workerExistsCalls++;
    final error = workerExistsError;
    if (error != null) throw error;
    final gate = workerExistsGate;
    if (gate != null) await gate;
    return workerExistsValue;
  }

  @override
  Future<String?> latestDeploymentId({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async => null;

  @override
  Future<CloudflareUploadSession> createUploadSession({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required List<CloudflareAssetManifestEntry> manifest,
  }) async {
    uploadManifests.add(List.unmodifiable(manifest));
    onCreateUploadSession?.call();
    final error = sessionError;
    if (error != null) throw error;
    return uploadSessionFactory?.call(manifest) ?? uploadSession;
  }

  @override
  Future<CloudflareCompletionToken> uploadBucket({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required List<CloudflareBucketAsset> assets,
  }) async {
    bucketCalls++;
    final error = uploadError;
    if (error != null) throw error;
    bucketUploads.add(List.unmodifiable(assets));
    onBucketUpload?.call(assets);
    return completionToken;
  }

  @override
  Future<void> deploy({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required CloudflareCompletionToken completionToken,
    required CloudflareDeploymentKind kind,
    required CloudflareDeployRecoveryCallback recovery,
  }) async {
    deployCalls++;
    deployRecovery = recovery;
    final error = deployError;
    if (error != null) throw error;
    onDeploy?.call();
  }

  @override
  Future<CloudflareWorkerRoute> readWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
  }) async {
    routeReadCalls++;
    final error = routeError;
    if (error != null) throw error;
    return route;
  }

  @override
  Future<CloudflareWorkerRoute> updateWorkerRoute({
    required CloudflareApiToken token,
    required CloudflareAccountId accountId,
    required CloudflareWorkerName workerName,
    required bool enabled,
    required bool previewsEnabled,
  }) async {
    routeUpdates.add(
      CloudflareWorkerRoute(enabled: enabled, previewsEnabled: previewsEnabled),
    );
    final error = routeError;
    if (error != null) throw error;
    return route = CloudflareWorkerRoute(
      enabled: enabled,
      previewsEnabled: previewsEnabled,
    );
  }
}

/// Encodes the deterministic marker expected by verification tests.
List<int> cloudflareTestMarkerBytes() =>
    const CloudflarePublishMarkerCodec().encode(
      const PublishMarker(
        publishId: cloudflareTestPublishId,
        publishedAt: cloudflareTestNow,
        state: PublishMarkerState.verification,
      ),
    );

/// One setup graph with replaceable fakes and deterministic time/ids.
final class CloudflareSetupHarness {
  /// Creates the graph, optionally with stored connection/journal state.
  CloudflareSetupHarness({
    CloudflareConnection? connection,
    PublishHostState? hostState,
    String? legacyGitHubRepo,
  }) : credentials = InMemoryCloudflareCredentialStore(connection),
       hostStore = FakePublishHostStateStore(hostState) {
    final hostRepository = PublishHostStateRepository(
      store: hostStore,
      manifest: _FakeManifest(legacyGitHubRepo),
      verifier: verifier,
    );
    final verifyAddress = VerifyCloudflareAddress(
      api: api,
      verifier: verifier,
      codec: const CloudflarePublishMarkerCodec(),
      sleep: (_) async {},
      clock: () => cloudflareTestNow,
      publishId: () => cloudflareTestPublishId,
      readBackAttempts: 1,
      readBackInterval: Duration.zero,
    );
    setup = SetupCloudflareSite(
      accountApi: api,
      deployApi: api,
      credentials: credentials,
      hostState: hostRepository,
      verifyAddress: verifyAddress,
      clock: () => cloudflareTestNow,
    );
  }

  /// API fake.
  final FakeCloudflareApi api = FakeCloudflareApi();

  /// Secure-record fake.
  final InMemoryCloudflareCredentialStore credentials;

  /// Public read-back fake.
  final FakePublishedSiteVerifier verifier = FakePublishedSiteVerifier();

  /// Host journal fake.
  final FakePublishHostStateStore hostStore;

  /// Use case under test.
  late final SetupCloudflareSite setup;
}
