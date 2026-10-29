import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_destination.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_move_reader.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publication_verifier.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_preflight.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_verified_state_commit.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';

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
  late ScriptedHostStore hostStore;
  late CloudflareMoveDestination destination;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitak_move_cf_dest_');
    api = FakeCloudflareApi();
    credentials = InMemoryCloudflareCredentialStore(cloudflareTestConnection());
    manifests = InMemoryCloudflareManifestStore();
    reader = FakeCloudflareWorkerReader()
      ..absent(CloudflareLimits.markerPath)
      ..absent('library.json');
    store = RecordingArtifactStore(FilePublishArtifactStore(baseDir: dir.path));
    hostStore = ScriptedHostStore(
      PublishHostState(
        activeHost: PublishHost.github,
        verifiedTarget: moveGitHubTarget,
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
    destination = CloudflareMoveDestination(
      reader: moveReader,
      deployApi: api,
      manifest: manifests,
      snapshotBuilder: _builder(),
      reads: FakeS8Reads(),
      artifactStores: () => store,
      markerCodec: _codec,
      markerProbe: probe,
      verifier: CloudflarePublicationVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 1,
      ),
      verifiedCommit: CloudflareVerifiedStateCommit(
        manifest: manifests,
        hostState: moveHostRepository(hostStore),
        credentials: credentials,
      ),
      clock: () => 1700000000000,
      publishId: () => moveRetiredPublishId,
    );
    api.onDeploy = () {
      api.workerExistsValue = true;
      for (final entry in store.bytesByPath.entries) {
        reader.body(entry.key, entry.value);
      }
    };
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<MoveSiteConfirmation> prepare() async {
    final result = await destination.prepare(
      oldTarget: moveGitHubTarget,
      newTarget: moveCloudflareTarget,
      sourceAnchor: moveAnchor(moveGitHubTarget),
    );
    return result.getOrElse((f) => fail('expected success, got $f'));
  }

  test('prepare is write-free and reviews the complete destination', () async {
    final confirmation = await prepare();

    expect(confirmation.digest, isNotEmpty);
    expect(confirmation.newTarget.targetId, moveCloudflareTarget.targetId);
    expect(api.deployCalls, 0);
    expect(api.uploadManifests, isEmpty);
    expect(
      reader.calls.map((call) => call.$2).toSet(),
      {CloudflareLimits.markerPath},
      reason: 'prepare may probe the marker, never a publish file',
    );
    expect(manifests.saves, isEmpty);
    expect(hostStore.saves, 0);
  });

  test('publish deploys the complete snapshot, verifies it, and commits live '
      'state without switching the old journal', () async {
    final confirmation = await prepare();

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    expect((result as MoveDestinationPublished).localStateSaved, isTrue);
    expect(api.deployCalls, 1);
    expect(api.routeUpdates.last.previewsEnabled, isFalse);
    expect(
      api.uploadManifests.single
          .map((entry) => entry.path.value)
          .toSet()
          .contains('index.html'),
      isTrue,
    );
    expect(manifests.current.state, PublishState.live);
    expect(manifests.current.publishId, moveRetiredPublishId);
    // The OLD site remains the journal's active/verified target until the
    // outer move records pending and retirement, then switches exactly once.
    expect(hostStore.stored!.activeHost, PublishHost.github);
    expect(
      hostStore.stored!.verifiedTarget!.targetId,
      moveGitHubTarget.targetId,
    );
    expect(hostStore.stored!.pendingMove, isNull);
  });

  test('N2: a destination whose Worker was deleted is reviewed as a recreate '
      'and publishes normally', () async {
    manifests.current = s8Manifest(
      target: moveCloudflareTarget,
      publishId: 'a' * 32,
    );

    final confirmation = await prepare();

    expect(confirmation.destinationWarning, contains('no longer exists'));
    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    expect(api.deployCalls, 1);
    expect(manifests.current.state, PublishState.live);
  });

  test('J.7 regression: a multi-bucket destination deploys with the final '
      "bucket's completion token", () async {
    api.uploadSessionFactory = cloudflareOneBucketPerHashSession;
    final confirmation = await prepare();

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    expect(api.bucketCalls, greaterThan(1));
    expect(api.deployCalls, 1);
    expect(api.deployedCompletionTokens, [
      api.completionToken.use((value) => value),
    ]);
    expect(manifests.current.state, PublishState.live);
  });

  test('a final bucket without a completion token stops the move before '
      'deployment', () async {
    api
      ..uploadSessionFactory = cloudflareOneBucketPerHashSession
      ..issueCompletionToken = false;
    final confirmation = await prepare();

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    final failure = result as MoveDestinationFailed;
    expect(failure.reason, CloudflareErrorMessages.uploadNotConfirmed);
    expect(api.deployCalls, 0);
    expect(manifests.saves, isEmpty);
    expect(hostStore.saves, 0);
  });

  test('a changed digest re-prompts before any upload or deploy', () async {
    final stale = await prepare();
    final tampered = MoveSiteConfirmation(
      oldTarget: stale.oldTarget,
      newTarget: stale.newTarget,
      sourceAnchor: stale.sourceAnchor,
      digest: 'tampered',
      catalogueItemCount: stale.catalogueItemCount,
      posterCount: stale.posterCount,
      availabilityOmitted: stale.availabilityOmitted,
    );

    final result = await destination.publish(
      confirmation: tampered,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationConfirmationRequired>());
    expect(api.uploadManifests, isEmpty);
    expect(api.deployCalls, 0);
  });

  test('a source change next to the deploy aborts the write', () async {
    final confirmation = await prepare();

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => false,
    );

    final failure = result as MoveDestinationFailed;
    expect(failure.reason, MoveSiteMessages.sourceChanged);
    expect(api.deployCalls, 0);
    expect(manifests.current.state, isNot(PublishState.live));
  });

  test(
    'an exact existing destination is verified without redeploying',
    () async {
      final confirmation = await prepare();
      await destination.publish(
        confirmation: confirmation,
        beforeWrite: () async => true,
      );
      final deploys = api.deployCalls;
      final uploads = api.uploadManifests.length;

      final preparedAgain = await destination.prepare(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
        sourceAnchor: moveAnchor(moveGitHubTarget),
      );
      final retried = await destination.publish(
        confirmation: preparedAgain.toNullable()!,
        beforeWrite: () async => true,
      );

      expect(retried, isA<MoveDestinationPublished>());
      expect(api.deployCalls, deploys);
      expect(api.uploadManifests, hasLength(uploads));
    },
  );
}

PublishSnapshotBuilder _builder() => PublishSnapshotBuilder(
  catalogue: CatalogueSectionBuilder(
    covers: PublishCoverDecider(
      coverIds: const PublishCoverIds(_FixedSalt()),
      readLocalCover: (_) async => null,
      fetchRemoteCover: (_) async => null,
    ),
    buildViewerHtml: () async => utf8.encode('<html>viewer</html>'),
    encodeBooksJson: encodeBooksJsonBytes,
  ),
  events: EventsSectionBuilder(
    readPoster: (_) async => null,
    buildEventsHtml: (posters) async =>
        utf8.encode('<html>${posters.length}</html>'),
    buildEventsJson: (posters) => utf8.encode('{"posters":[]}'),
  ),
);

final class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt();

  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}
