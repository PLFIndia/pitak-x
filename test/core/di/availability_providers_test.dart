import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_ids_changes.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/infrastructure/commit_recording_github_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/publish/support/availability_lane_fakes.dart';
import '../../features/publish/support/cloudflare_fakes.dart';
import '../../features/publish/support/cloudflare_s8_fakes.dart';
import '../../features/publish/support/github_lane_fakes.dart';

/// The availability wiring (plan C.11 `core/di/src/availability_providers`).
void main() {
  test('this build runs the lane (plan S8; the kill switch is on)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(availabilityLaneActivatedProvider), isTrue);
  });

  test('every GitHub commit goes through the recording decorator', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(gitHubApiProvider), isA<CommitRecordingGitHubApi>());
  });

  test(
    'a recorded commit lands in the lane store (the hourly budget)',
    () async {
      final store = MemoryAvailabilityLaneStore();
      final container = ProviderContainer(
        overrides: [
          availabilityLaneRepositoryProvider.overrideWith(
            (ref) async => AvailabilityLaneRepository(store),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gitHubCommitRecorderProvider)(1234);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(store.saved!.gitHubCommitTimes, [1234]);
    },
  );

  test(
    'an unavailable lane store never fails the commit (best effort)',
    () async {
      final container = ProviderContainer(
        overrides: [
          availabilityLaneRepositoryProvider.overrideWith(
            (ref) async => throw StateError('no prefs'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gitHubCommitRecorderProvider)(1);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      // Reaching here without an uncaught error is the assertion.
    },
  );

  test('the keys reset clears both records and signals the lane', () async {
    final gitHub = LaneMemManifest(
      const PublishManifest(
        repo: 'me/lib',
        fileShas: {'books.json': 'b1'},
        catalogueKeyed: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        publishManifestStoreProvider.overrideWith((ref) async => gitHub),
        cloudflareManifestStoreProvider.overrideWith(
          (ref) async => InMemoryCloudflareManifestStore(),
        ),
        availabilityLaneRepositoryProvider.overrideWith(
          (ref) async =>
              AvailabilityLaneRepository(MemoryAvailabilityLaneStore()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final reset = await container.read(catalogueKeysResetProvider.future);
    await reset.beforeIdsChange(() async {});

    expect(gitHub.current.catalogueKeyed, isFalse);
    expect(container.read(catalogueIdsChangesProvider), 1);
  });

  test('the runner wires both hosts over the shared providers', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('pitak_lane_di');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        publishManifestStoreProvider.overrideWith(
          (ref) async => LaneMemManifest(),
        ),
        cloudflareManifestStoreProvider.overrideWith(
          (ref) async => InMemoryCloudflareManifestStore(),
        ),
        publishHostStateStoreProvider.overrideWith(
          (ref) async => FakePublishHostStateStore(
            const PublishHostState(activeHost: PublishHost.cloudflare),
          ),
        ),
        cloudflareCredentialStoreProvider.overrideWithValue(
          InMemoryCloudflareCredentialStore(),
        ),
        appDocsDirProvider.overrideWith((ref) async => tmp),
        appTempDirProvider.overrideWith((ref) async => tmp),
      ],
    );
    addTearDown(container.dispose);

    final runner = await container.read(
      availabilityPublishRunnerProvider.future,
    );
    expect(container.read(availabilityItemKeysProvider), isNotNull);

    // Cloudflare is active but not connected: a fixed sentence, no network.
    final target = await runner.currentTarget();
    expect(target.isLeft(), isTrue);
    final run = await runner(const AvailabilityDelete());
    expect(run, isA<AvailabilityRunBlocked>());
  });
}
