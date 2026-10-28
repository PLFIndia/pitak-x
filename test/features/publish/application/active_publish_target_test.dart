import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/active_publish_target.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/cloudflare_fakes.dart';
import '../support/cloudflare_s8_fakes.dart';

final class _GitHubCredentials implements PublishCredentialStore {
  _GitHubCredentials(this.repo);

  final String? repo;
  int targetReads = 0;
  int tokenReads = 0;

  @override
  Future<String?> targetRepo() async {
    targetReads++;
    return repo;
  }

  @override
  Future<String?> token() async {
    tokenReads++;
    return 'synthetic-token';
  }

  @override
  Future<void> clearTargetRepo() async {}
  @override
  Future<void> clearToken() async {}
  @override
  Future<void> setTargetRepo(String target) async {}
  @override
  Future<void> setToken(String token) async {}
}

final class _CountingManifest implements PublishManifestGateway {
  int loads = 0;

  @override
  PublishManifest load() {
    loads++;
    return PublishManifest.empty;
  }

  @override
  Either<Failure, Unit> save(PublishManifest manifest) => right(unit);
}

void main() {
  late _GitHubCredentials gitHub;
  late InMemoryCloudflareCredentialStore cloudflare;
  late _CountingManifest manifest;

  ActivePublishTargetResolver resolver(PublishHostState? journal) {
    return ActivePublishTargetResolver(
      hostState: PublishHostStateRepository(
        store: FakePublishHostStateStore(journal),
        manifest: manifest,
        verifier: FakePublishedSiteVerifier(),
      ),
      gitHubCredentials: gitHub,
      cloudflareCredentials: cloudflare,
    );
  }

  setUp(() {
    gitHub = _GitHubCredentials('me/lib');
    cloudflare = InMemoryCloudflareCredentialStore(cloudflareTestConnection());
    manifest = _CountingManifest();
  });

  test(
    'Cloudflare active uses only Cloudflare credentials and exact target',
    () async {
      final result = await resolver(
        const PublishHostState(activeHost: PublishHost.cloudflare),
      ).call();

      expect(result.toNullable(), isA<CloudflarePublishTarget>());
      expect(gitHub.targetReads, 0);
      expect(manifest.loads, 0);
    },
  );

  test(
    'GitHub active stays GitHub even when Cloudflare is configured',
    () async {
      final result = await resolver(
        const PublishHostState(activeHost: PublishHost.github),
      ).call();

      expect(result.toNullable(), isA<GitHubPublishTarget>());
      expect((result.toNullable()! as GitHubPublishTarget).ownerRepo, 'me/lib');
      expect(cloudflare.reads, 0);
      expect(manifest.loads, 0);
    },
  );

  test(
    'an absent journal uses the legacy GitHub default without manifest IO',
    () async {
      final result = await resolver(null).call();

      expect(result.toNullable(), isA<GitHubPublishTarget>());
      expect(manifest.loads, 0);
      expect(cloudflare.reads, 0);
    },
  );

  test('an existing journal with no active host does not fall back', () async {
    final result = await resolver(PublishHostState.empty).call();

    expect(result.isLeft(), isTrue);
    expect(gitHub.targetReads, 0);
    expect(cloudflare.reads, 0);
    expect(manifest.loads, 0);
  });

  test('PublishController routes Cloudflare-active work through the shared '
      'factory and never reads GitHub credentials', () async {
    final dir = await Directory.systemTemp.createTemp('pitaka_s8_route_');
    addTearDown(() => dir.delete(recursive: true));
    final h = S8PublishHarness(
      dir,
      hostState: const PublishHostState(activeHost: PublishHost.cloudflare),
    );
    final factoryReads = <PublishReads>[];
    final container = ProviderContainer(
      overrides: [
        publishHostStateRepositoryProvider.overrideWith(
          (ref) async => h.hostRepository,
        ),
        cloudflareCredentialStoreProvider.overrideWithValue(h.credentials),
        publishCredentialStoreProvider.overrideWithValue(gitHub),
        publishToCloudflareUseCaseProvider.overrideWith(
          (ref) async => (PublishReads reads) {
            factoryReads.add(reads);
            return h.useCase;
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(publishControllerProvider.notifier)
        .publish();

    expect(result, isA<PublishSuccess>());
    expect(factoryReads, hasLength(1));
    expect(factoryReads.single, isA<PublishController>());
    expect(h.api.deployCalls, 1);
    expect(gitHub.targetReads, 0);
    expect(gitHub.tokenReads, 0);
  });
}
