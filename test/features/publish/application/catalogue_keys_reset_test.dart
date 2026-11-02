import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_keys_reset.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

import '../support/availability_lane_fakes.dart';
import '../support/key_set_fixtures.dart';

/// Plan J9, decided in S6: a flow that changes what item ids name first
/// marks the published keys unusable, inside the publish queue.
void main() {
  const keyedGitHub = PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'HEAD',
    fileShas: {'books.json': 'b1', 'availability.json': 'a1'},
    catalogueKeyed: true,
  );
  final cloudflareTarget = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;
  final keyedCloudflare = CloudflareSiteManifest(
    target: cloudflareTarget,
    publishId: 'a' * 32,
    catalogueKeyed: true,
  );
  final set = AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: const ['0000000000000001'],
    asOfMillis: 60000,
  )!;

  MemoryKeysReset seeded() {
    final keys = MemoryKeysReset();
    keys.gitHub.current = keyedGitHub;
    keys.cloudflare
      ..current = keyedCloudflare
      ..pending = keyedCloudflare;
    return keys;
  }

  test('clears every flag and the lane sets, then runs the change and tells '
      'the lane', () async {
    final keys = seeded();
    await keys.laneStore.write(
      AvailabilityLaneState(
        pending: set,
        gitHubCommitTimes: const [7],
        noticeShown: true,
      ),
    );
    var flagsWhenChangeRan = <bool>[];

    final result = await keys.reset.beforeIdsChange(() async {
      flagsWhenChangeRan = [
        keys.gitHub.current.catalogueKeyed,
        keys.cloudflare.current.catalogueKeyed,
        keys.cloudflare.pending.catalogueKeyed,
      ];
      expect(keys.idsChanged, 0, reason: 'told only after the change');
      return 'done';
    });

    expect(result, 'done');
    expect(flagsWhenChangeRan, [false, false, false]);
    expect(keys.gitHub.current.shaFor('availability.json'), 'a1');
    final lane = keys.laneStore.saved!;
    expect(lane.pending, isNull);
    expect(lane.published, isNull);
    expect(lane.gitHubCommitTimes, [7], reason: 'the budget is not a key');
    expect(lane.noticeShown, isTrue);
    expect(keys.idsChanged, 1);
  });

  test('an unkeyed record is not rewritten', () async {
    final keys = MemoryKeysReset();
    await keys.reset.beforeIdsChange(() async {});
    expect(keys.gitHub.saves, isEmpty);
    expect(keys.cloudflare.saves, isEmpty);
    expect(keys.cloudflare.pendingSaves, isEmpty);
  });

  group('ADR 0020 Decision 4: local cover sources are forgotten too', () {
    // A restore switches to a covers folder built from the archive, so a
    // file name a record knows may now hold other bytes. The next publish
    // must read those covers again instead of reusing them by name.
    const localAndRemote = {
      '1': 'covers/one.jpg',
      '2': 'file:///data/covers/two.jpg',
      '3': 'https://covers.example/3.jpg',
    };

    test('in all three records, before the change runs; remote sources, the '
        'rendition and the files stay', () async {
      final keys = MemoryKeysReset();
      keys.gitHub.current = const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'HEAD',
        fileShas: {'books.json': 'b1', 'covers/x.jpg': 'c1'},
        coverUrlByBookId: localAndRemote,
        coverRendition: 1,
      );
      final cloudflare = CloudflareSiteManifest(
        target: cloudflareTarget,
        publishId: 'a' * 32,
        coverUrlByBookId: localAndRemote,
        coverRendition: 1,
      );
      keys.cloudflare
        ..current = cloudflare
        ..pending = cloudflare;
      var sourcesWhenChangeRan = <Map<String, String>>[];

      await keys.reset.beforeIdsChange(() async {
        sourcesWhenChangeRan = [
          keys.gitHub.current.coverUrlByBookId,
          keys.cloudflare.current.coverUrlByBookId,
          keys.cloudflare.pending.coverUrlByBookId,
        ];
      });

      const remoteOnly = {'3': 'https://covers.example/3.jpg'};
      expect(sourcesWhenChangeRan, [remoteOnly, remoteOnly, remoteOnly]);
      expect(keys.gitHub.current.coverRendition, 1);
      expect(keys.gitHub.current.shaFor('covers/x.jpg'), 'c1');
      expect(keys.cloudflare.current.coverRendition, 1);
    });

    test('a record with remote covers only is not rewritten', () async {
      final keys = MemoryKeysReset();
      keys.gitHub.current = const PublishManifest(
        repo: 'me/lib',
        coverUrlByBookId: {'3': 'https://covers.example/3.jpg'},
      );
      await keys.reset.beforeIdsChange(() async {});
      expect(keys.gitHub.saves, isEmpty);
    });

    test('a failed save refuses the change (fail closed)', () async {
      final keys = MemoryKeysReset();
      keys.gitHub
        ..current = const PublishManifest(
          repo: 'me/lib',
          coverUrlByBookId: {'1': 'covers/one.jpg'},
        )
        ..saveFails = true;
      var ran = false;
      await expectLater(
        keys.reset.beforeIdsChange(() async => ran = true),
        throwsA(isA<CatalogueKeysResetRefused>()),
      );
      expect(ran, isFalse);
    });
  });

  for (final failing in ['github', 'cloudflare', 'attempt', 'lane']) {
    test('a $failing save failure refuses the change (fail closed)', () async {
      final keys = seeded();
      switch (failing) {
        case 'github':
          keys.gitHub.saveFails = true;
        case 'cloudflare':
          keys.cloudflare.failSave = true;
        case 'attempt':
          keys.cloudflare.failPendingSave = true;
        case 'lane':
          keys.laneStore.failWrites = true;
      }
      var ran = false;

      await expectLater(
        keys.reset.beforeIdsChange(() async => ran = true),
        throwsA(isA<CatalogueKeysResetRefused>()),
      );

      expect(ran, isFalse);
      expect(keys.idsChanged, 0);
    });
  }

  test('the change runs inside the publish queue: a publish waits', () async {
    final keys = seeded();
    final order = <String>[];

    final reset = keys.reset.beforeIdsChange(() async {
      order.add('change');
      await Future<void>.delayed(Duration.zero);
      order.add('change done');
    });
    final publish = keys.queue.enqueue(() async => order.add('publish'));
    await Future.wait([reset, publish]);

    expect(order, ['change', 'change done', 'publish']);
  });

  test('the refusal reads as a fixed, safe sentence', () {
    expect(
      const CatalogueKeysResetRefused().toString(),
      'Pitak could not update its publishing record. Nothing was changed.',
    );
  });
}
