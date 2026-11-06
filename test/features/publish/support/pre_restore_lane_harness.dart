import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';
import 'package:pitaka/features/publish/application/site/active_publish_target.dart';
import 'package:pitaka/features/publish/application/site/publish_going_live_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../restore/restore_use_case_harness.dart';
import 'cloudflare_fakes.dart';
import 'cloudflare_s8_fakes.dart';
import 'github_lane_fakes.dart';
import 'going_live_fakes.dart';

final class _GitHubCredentials implements PublishCredentialStore {
  @override
  Future<String?> targetRepo() async => 'me/lib';
  @override
  Future<String?> token() async => 'synthetic-token';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected credential operation');
}

/// A GitHub write probe. Every other operation is unexpected in a guard test.
final class GitHubWriteProbe implements GitHubApi {
  int commitRequests = 0;

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
    Future<void> Function(String gitSha)? onBlobStored,
  }) async {
    commitRequests++;
    throw StateError('a refused publish reached GitHub');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected GitHub operation');
}

/// Real guard wiring over an empty real-Drift catalogue and scriptable site.
final class PreRestoreLaneHarness {
  PreRestoreLaneHarness({
    required this.useCloudflare,
    List<Override> extraOverrides = const [],
  }) {
    final connection = cloudflareTestConnection();
    cloudflareCredentials = InMemoryCloudflareCredentialStore(connection);
    target = useCloudflare
        ? connection.status.target!
        : GitHubPublishTarget.create('me/lib')!;
    final hostState = FakePublishHostStateStore(
      PublishHostState(
        activeHost: useCloudflare ? PublishHost.cloudflare : PublishHost.github,
      ),
    );
    hostRepository = PublishHostStateRepository(
      store: hostState,
      manifest: manifest,
      verifier: FakePublishedSiteVerifier(),
    );
    resolver = ActivePublishTargetResolver(
      hostState: hostRepository,
      gitHubCredentials: _GitHubCredentials(),
      cloudflareCredentials: cloudflareCredentials,
    );
    container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => restore.fixture.books,
        ),
        periodicalRepositoryProvider.overrideWith(
          (ref) async => restore.fixture.periodicals,
        ),
        restoreIdentityJournalStoreProvider.overrideWith(
          (ref) async => restore.journal,
        ),
        publishedSiteReadVerifierProvider.overrideWithValue(restore.reader),
        publishedCatalogueDecoderProvider.overrideWithValue(
          (bytes) async => const PublishedCatalogueCodec().decode(bytes),
        ),
        activePublishTargetResolverProvider.overrideWith(
          (ref) async => resolver,
        ),
        publishHostStateRepositoryProvider.overrideWith(
          (ref) async => hostRepository,
        ),
        publishOperationQueueProvider.overrideWithValue(SerialOpQueue()),
        gitHubApiProvider.overrideWithValue(gitHub),
        cloudflareApiProvider.overrideWithValue(cloudflareApi),
        cloudflareCredentialStoreProvider.overrideWithValue(
          cloudflareCredentials,
        ),
        publishManifestStoreProvider.overrideWith((ref) async => manifest),
        cloudflareManifestStoreProvider.overrideWith(
          (ref) async => cloudflareManifest,
        ),
        publishGoingLiveProvider.overrideWith(() => goingLive),
        ...extraOverrides,
      ],
    );
  }

  final bool useCloudflare;
  final restore = RestoreUseCaseHarness();
  final gitHub = GitHubWriteProbe();
  final cloudflareApi = FakeCloudflareApi();
  final manifest = LaneMemManifest();
  final cloudflareManifest = InMemoryCloudflareManifestStore();
  final goingLive = RecordingPublishGoingLive();
  late final InMemoryCloudflareCredentialStore cloudflareCredentials;
  late final PublishHostStateRepository hostRepository;
  late final PublishTarget target;
  late final ActivePublishTargetResolver resolver;
  late final ProviderContainer container;

  /// Makes the remote recovery copy contain one readable item.
  void remoteHasRecoveryData() {
    restore.reader.outcome = PublishedSiteReadBody(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'books': [
            {'title': 'Recovery book'},
          ],
        }),
      ),
    );
  }

  /// Makes the durable journal block the write before remote reads.
  void pendingJournal() {
    restore.journal.value = RestoreIdentityJournal(
      siteUrl: target.siteUrl,
      addedDate: restore.now,
      fingerprint: restore.fingerprint,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await restore.dispose();
  }
}
