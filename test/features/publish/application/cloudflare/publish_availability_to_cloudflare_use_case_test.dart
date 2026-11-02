import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';
import '../../support/key_set_fixtures.dart';

/// Plan S5 (ADR 0019 Decision 11, plan AV13/C.6): the availability lane's
/// Cloudflare publish, against the fake API.
///
/// What the ADR asks S5 to prove: exactly two uploads; the read-back scope;
/// never a replacement; every gate still runs. The plan's exit adds: proven
/// against the fake API, including the missing-bytes and stale branches.
void main() {
  late Directory dir;

  final previousId = 'a' * 32;
  final defaultTarget = cloudflareTestConnection().status.target!;

  /// The rest of a real site, so "every other file is carried" means
  /// something: an events page, a poster and a cover.
  final siteExtras = <String, PublishFile>{
    'events.html': s8File('events.html', utf8.encode('<html>1</html>')),
    'events.json': s8File('events.json', utf8.encode('{"posters":[1]}')),
    'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
    'covers/1.jpg': s8File('covers/1.jpg', [4, 5, 6]),
  };

  AvailabilitySnapshot snapshot(List<String> keys) =>
      AvailabilitySnapshot.tryCreate(
        keySet: testKeySetId,
        keys: keys,
        asOfMillis: 61000,
      )!;

  final setA = snapshot(['0123456789abcdef']);
  final setB = snapshot(['0123456789abcdef', 'fedcba9876543210']);

  /// `availability.json` exactly as the one encoder writes [set].
  PublishFile availabilityFile(AvailabilitySnapshot set) => s8File(
    'availability.json',
    encodeAvailabilityJsonBytes(AvailabilityDocument(set)),
  );

  /// Every file of the site this phone last published, marker included.
  Map<String, PublishFile> siteFiles({AvailabilitySnapshot? published}) => {
    ...s8CoreFiles(previousId),
    ...siteExtras,
    if (published != null) 'availability.json': availabilityFile(published),
  };

  /// This phone's record of that site.
  CloudflareSiteManifest record({
    PublishState state = PublishState.live,
    bool keyed = true,
    AvailabilitySnapshot? published,
  }) => s8Manifest(
    target: defaultTarget,
    publishId: previousId,
    state: state,
    additional: {
      ...siteExtras,
      if (published != null) 'availability.json': availabilityFile(published),
    },
    catalogueKeyed: keyed,
  );

  void seed(S8PublishHarness h, Map<String, PublishFile> files) {
    for (final entry in files.entries) {
      h.reader.body(entry.key, entry.value.bytes);
    }
  }

  void alreadyVerified(S8PublishHarness h) {
    h.hostStore.stored = PublishHostState(
      activeHost: PublishHost.cloudflare,
      verifiedTarget: h.target,
    );
    h.credentials.record = h.credentials.record!.markWorkersWriteReadBack();
  }

  /// A phone whose last publish is live on the Worker and proven.
  S8PublishHarness publishedSite({
    PublishState state = PublishState.live,
    bool keyed = true,
    AvailabilitySnapshot? published,
  }) {
    final h = S8PublishHarness(
      dir,
      workerExists: true,
      manifest: record(state: state, keyed: keyed, published: published),
    );
    seed(h, siteFiles(published: published));
    alreadyVerified(h);
    return h;
  }

  /// Like Cloudflare: the session asks only for hashes it does not hold yet,
  /// one bucket each. Everything the last version had is already there.
  CloudflareUploadSession Function(List<CloudflareAssetManifestEntry>)
  dedupAgainst(CloudflareSiteManifest previous) {
    final held = {for (final entry in previous.files.values) entry.hash};
    return (manifest) => CloudflareUploadSession.tryCreate(
      uploadJwt: 'synthetic-upload-jwt',
      buckets: [
        for (final hash in {for (final entry in manifest) entry.hash})
          if (!held.contains(hash)) [hash],
      ],
    )!;
  }

  /// The read-back reads, told apart from the marker probes by their cache
  /// buster (`<revision>-<round>`; probes use `preflight-…`, `final-…`).
  List<String> readBackPaths(S8PublishHarness h) => [
    for (final call in h.reader.calls)
      if (RegExp(r'^\d+-\d+$').hasMatch(call.$4 ?? '')) call.$2,
  ];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_s5_availability_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('a write', () {
    test('deploys one version that changes only availability.json; '
        'Cloudflare is sent exactly two files', () async {
      final h = publishedSite();
      final previous = h.manifestStore.current;
      h.api.uploadSessionFactory = dedupAgainst(previous);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityLive>());
      final live = result as AvailabilityLive;
      expect(live.acceptedAt, cloudflareTestNow);
      expect(live.localStateSaved, isTrue);
      expect(h.api.deployCalls, 1);

      // The phone produced bytes for exactly two files...
      expect(h.artifactStore.bytesByPath.keys.toSet(), {
        'availability.json',
        CloudflareLimits.markerPath,
      });
      // ...and those two are all Cloudflare received.
      final current = h.manifestStore.current;
      final sent = h.api.bucketUploads.expand((bucket) => bucket);
      expect(sent.map((asset) => asset.hash).toSet(), {
        current.entryFor('availability.json')!.hash,
        current.entryFor(CloudflareLimits.markerPath)!.hash,
      });
      expect(sent, hasLength(2));

      // The version is still complete: every other file by its old hash.
      final manifest = {
        for (final entry in h.api.uploadManifests.single)
          entry.path.value: entry.hash,
      };
      expect(manifest.keys.toSet(), {
        ...previous.files.keys,
        'availability.json',
      });
      for (final path in previous.files.keys) {
        if (path == CloudflareLimits.markerPath) continue;
        expect(manifest[path], previous.entryFor(path)!.hash, reason: path);
      }
    });

    test('saves the record deployed, then live, still keyed, with the file '
        'and the fresh marker', () async {
      final h = publishedSite();

      await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(h.manifestStore.saves.map((m) => m.state), [
        PublishState.deployed,
        PublishState.live,
      ]);
      final current = h.manifestStore.current;
      expect(current.publishId, cloudflareTestPublishId);
      expect(
        current.shaFor('availability.json'),
        availabilityFile(setA).gitSha,
      );
      // books.json was carried unchanged, so the keyed flag carries too.
      expect(current.shaFor('books.json'), siteFiles()['books.json']!.gitSha);
      expect(current.catalogueKeyed, isTrue);
      expect(h.manifestStore.pending.target, isNull);
    });

    test('reads back only the fresh marker and availability.json, and the '
        'first round reads at once (AV13)', () async {
      final h = publishedSite();

      await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(readBackPaths(h).toSet(), {
        CloudflareLimits.markerPath,
        'availability.json',
      });
      expect(readBackPaths(h), hasLength(2), reason: 'one round, two reads');
      expect(h.readBackWaits, isEmpty, reason: 'no wait before round one');
    });

    test('an unchanged set deploys nothing', () async {
      final h = publishedSite(published: setA);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(snapshot(['0123456789abcdef'])),
      );

      expect(result, isA<AvailabilityAlreadyPublished>());
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    });

    test('a changed set replaces the recorded file', () async {
      final h = publishedSite(published: setA);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setB),
      );

      expect(result, isA<AvailabilityLive>());
      expect(
        h.manifestStore.current.shaFor('availability.json'),
        availabilityFile(setB).gitSha,
      );
    });

    test('an empty set is published as a real answer', () async {
      final h = publishedSite(published: setA);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(snapshot(const [])),
      );

      expect(result, isA<AvailabilityLive>());
      final bytes = h.artifactStore.bytesByPath['availability.json']!;
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(decoded['out'], isEmpty);
    });

    test('a read-back that runs out: going live, the record stays deployed, '
        'and there is no deferred check on Cloudflare', () async {
      final h = publishedSite()..autoServe = false;

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityGoingLive>());
      final goingLive = result as AvailabilityGoingLive;
      expect(goingLive.verification, isNull);
      expect(goingLive.localStateSaved, isTrue);
      expect(h.manifestStore.current.state, PublishState.deployed);
      // The after-deploy budget, first round immediate: 12 rounds, 11 waits.
      const budget = CloudflareReadBackBudget.afterAvailabilityDeploy;
      expect(h.readBackWaits, hasLength(budget.rounds - 1));
      expect(h.readBackWaits, everyElement(budget.interval));
    });

    test('a record that cannot be saved after the deploy: live, but not all '
        'of it recorded', () async {
      final h = publishedSite();
      h.manifestStore.failSave = true;

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityLive>());
      expect((result as AvailabilityLive).localStateSaved, isFalse);
    });

    test(
      'a spool that cannot be cleaned up does not change the outcome',
      () async {
        final h = publishedSite();
        h.artifactStore.failDispose = true;

        final result = await h.availabilityUseCase(
          target: h.target,
          update: AvailabilityWrite(setA),
        );

        expect(result, isA<AvailabilityLive>());
      },
    );
  });

  group("gate 7b: the live books.json is this phone's own keyed publish", () {
    test(
      'an unkeyed record: not ready, nothing uploaded or deployed',
      () async {
        final h = publishedSite(keyed: false);

        final result = await h.availabilityUseCase(
          target: h.target,
          update: AvailabilityWrite(setA),
        );

        expect(result, isA<AvailabilityNotReady>());
        expect(
          (result as AvailabilityNotReady).reason,
          AvailabilityPublishMessages.catalogueNotKeyed,
        );
        expect(h.api.uploadManifests, isEmpty);
        expect(h.api.routeUpdates, isEmpty);
        expect(h.api.deployCalls, 0);
        expect(readBackPaths(h), isEmpty);
        expect(result.staleFileRecorded, isFalse);
      },
    );

    test('an unkeyed record that still shows the file reports it, so the '
        'lane removes it (plan S6)', () async {
      final h = publishedSite(keyed: false, published: setA);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setB),
      );

      expect((result as AvailabilityNotReady).staleFileRecorded, isTrue);
      expect(h.api.deployCalls, 0, reason: 'the use case itself sends none');
    });

    test('no record for this Worker (a fresh phone): not ready', () async {
      final h = S8PublishHarness(dir, workerExists: true);
      h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityNotReady>());
      expect(h.api.deployCalls, 0);
    });

    test(
      'a record for another Worker claims nothing here: not ready',
      () async {
        final other = cloudflareTestConnection()
            .selectSubdomain(
              CloudflareSubdomain.tryParse('library')!,
              confirmed: true,
            )
            .selectWorker(CloudflareWorkerName.tryParse('other-library')!);
        final h = S8PublishHarness(
          dir,
          connection: other,
          workerExists: true,
          manifest: record(),
        );

        final result = await h.availabilityUseCase(
          target: h.target,
          update: AvailabilityWrite(setA),
        );

        expect(result, isA<AvailabilityNotReady>());
        expect(h.api.deployCalls, 0);
      },
    );
  });

  group('the lane never replaces a site: it asks for a repair', () {
    Future<void> expectRepair(
      S8PublishHarness h, {
      AvailabilityUpdate? update,
    }) async {
      final result = await h.availabilityUseCase(
        target: h.target,
        update: update ?? AvailabilityWrite(setA),
      );
      expect(result, isA<AvailabilityPending>());
      expect(
        (result as AvailabilityPending).reason,
        AvailabilityPublishMessages.repairSite,
      );
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.pendingSaves, isEmpty);
      // A replacement review would read the whole library; the lane reads
      // nothing of it, ever.
      expect(h.reads.calls, isEmpty);
      expect(h.reads.libraryJsonCalls, 0);
    }

    test("another phone's marker", () async {
      final h = publishedSite();
      h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));

      await expectRepair(h);
      expect(h.api.uploadManifests, isEmpty);
    });

    test('a retired marker (the site was moved away)', () async {
      final h = publishedSite();
      h.reader.body(
        CloudflareLimits.markerPath,
        s8Marker('b' * 32, state: PublishMarkerState.retired),
      );

      await expectRepair(h);
    });

    test('an unreadable marker', () async {
      final h = publishedSite();
      h.reader.unreadable(CloudflareLimits.markerPath);

      await expectRepair(h);
    });

    test('a Worker that no longer exists', () async {
      final h = publishedSite();
      h.api.workerExistsValue = false;
      h.reader.absent(CloudflareLimits.markerPath);

      await expectRepair(h);
    });

    test('a deployed record the live site contradicts', () async {
      final h = publishedSite(state: PublishState.deployed);
      h.reader.body('books.json', utf8.encode('{"books":["someone else"]}'));

      await expectRepair(h);
      expect(h.api.uploadManifests, isEmpty);
    });

    test('missing bytes: Cloudflare asks for a carried file this phone does '
        'not have; nothing is uploaded or deployed', () async {
      final h = publishedSite();
      final posterHash = h.manifestStore.current
          .entryFor('posters/a.jpg')!
          .hash;
      h.api.uploadSessionFactory = (_) => CloudflareUploadSession.tryCreate(
        uploadJwt: 'synthetic-upload-jwt',
        buckets: [
          [posterHash],
        ],
      )!;

      await expectRepair(h);
      expect(h.api.bucketCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    });

    test('carried hashes from an older formula cannot be trusted: stops '
        'before any upload session', () async {
      final h = publishedSite();
      final trusted = h.manifestStore.current;
      h.manifestStore.current = CloudflareSiteManifest(
        target: trusted.target,
        publishId: trusted.publishId,
        state: trusted.state,
        files: trusted.files,
        catalogueKeyed: true,
      );

      await expectRepair(h);
      expect(h.api.uploadManifests, isEmpty);
    });

    test('a removal over a site this phone did not publish last', () async {
      final h = publishedSite(published: setA);
      h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));

      await expectRepair(h, update: const AvailabilityDelete());
    });
  });

  group('every gate of an ordinary deploy still runs', () {
    test('Version URLs are proven off before the session and after the '
        'deploy', () async {
      final h = publishedSite();
      // The fake starts with previews ON (a route changed outside Pitak).
      expect(h.api.route.previewsEnabled, isTrue);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityLive>());
      expect(h.api.routeUpdates, hasLength(2));
      expect(h.api.routeUpdates.map((r) => r.previewsEnabled), [false, false]);
      expect(h.api.routeUpdates.last.enabled, isTrue);
    });

    test('a Version-URL failure stops before any upload or deploy', () async {
      final h = publishedSite();
      h.api.routeUpdateError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityPending>());
      expect(
        (result as AvailabilityPending).reason,
        contains(CloudflareErrorMessages.liveUnchanged),
      );
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
    });

    test('stale: the site changed during the publish, so nothing is '
        'deployed and the lane retries later', () async {
      final h = publishedSite();
      h.api.onCreateUploadSession = () =>
          h.reader.body(CloudflareLimits.markerPath, s8Marker('c' * 32));

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityPending>());
      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.stalePublish,
      );
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    });

    test(
      'an attempt that cannot be recorded first is never sent (L4)',
      () async {
        final h = publishedSite();
        h.manifestStore.failPendingSave = true;

        final result = await h.availabilityUseCase(
          target: h.target,
          update: AvailabilityWrite(setA),
        );

        expect(
          (result as AvailabilityPending).reason,
          CloudflareErrorMessages.localRecordNotSavedBeforeDeploy,
        );
        expect(h.api.deployCalls, 0);
      },
    );

    test('a deploy whose response was lost is recognised on the next run, '
        'which then has nothing left to send (L4)', () async {
      final h = publishedSite();
      h.api
        ..onDeployAttempt = h.serveDeployed
        ..deployError = CloudflareApiException(
          CloudflareApiExceptionKind.server,
        );

      final first = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(
        (first as AvailabilityPending).reason,
        contains(CloudflareErrorMessages.deployUncertain),
      );
      expect(h.manifestStore.pending.publishId, cloudflareTestPublishId);

      h
        ..api.deployError = null
        ..nextPublishId = 'b' * 32;
      final second = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(second, isA<AvailabilityAlreadyPublished>());
      expect(h.api.deployCalls, 1, reason: 'only the first attempt');
      final current = h.manifestStore.current;
      expect(current.publishId, cloudflareTestPublishId);
      expect(current.state, PublishState.live);
      expect(
        current.shaFor('availability.json'),
        availabilityFile(setA).gitSha,
      );
      expect(h.manifestStore.pending.target, isNull);
    });

    test('an earlier unproven deploy is proven first, then the new set '
        'deploys', () async {
      final h = publishedSite(state: PublishState.deployed, published: setA);

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setB),
      );

      expect(result, isA<AvailabilityLive>());
      expect(
        h.manifestStore.saves.map((m) => (m.publishId, m.state)).toList(),
        [
          (previousId, PublishState.live),
          (cloudflareTestPublishId, PublishState.deployed),
          (cloudflareTestPublishId, PublishState.live),
        ],
      );
    });

    test('an earlier deploy that cannot be checked does not block the lane; '
        'the new read-back decides', () async {
      final h = publishedSite(state: PublishState.deployed);
      h.reader.unreadable('books.json');

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(result, isA<AvailabilityLive>());
      expect(h.api.deployCalls, 1);
    });

    test('a Version-URL failure while proving an earlier deploy keeps the '
        'fixed sentence', () async {
      final h = publishedSite(state: PublishState.deployed);
      h.api.routeUpdateError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.versionUrlPrivacy,
      );
      expect(h.api.deployCalls, 0);
    });
  });

  group('a removal (the switch is off)', () {
    test('deploys one version without availability.json, sends only the '
        'marker, and proves the exact 404', () async {
      final h = publishedSite(published: setA);
      h.api
        ..uploadSessionFactory = dedupAgainst(h.manifestStore.current)
        ..onDeploy = () {
          h.serveDeployed();
          h.reader.absent('availability.json');
        };

      final result = await h.availabilityUseCase(
        target: h.target,
        update: const AvailabilityDelete(),
      );

      expect(result, isA<AvailabilityLive>());
      final paths = h.api.uploadManifests.single.map((e) => e.path.value);
      expect(paths, isNot(contains('availability.json')));
      expect(paths, containsAll(siteExtras.keys));
      expect(h.api.bucketUploads.expand((bucket) => bucket), hasLength(1));
      expect(h.artifactStore.bytesByPath.keys, [CloudflareLimits.markerPath]);
      expect(readBackPaths(h).toSet(), {
        CloudflareLimits.markerPath,
        'availability.json',
      });
      final current = h.manifestStore.current;
      expect(current.entryFor('availability.json'), isNull);
      expect(current.catalogueKeyed, isTrue);
      expect(current.state, PublishState.live);
    });

    test('needs no gate 7b: deleting is always the safe direction', () async {
      final h = publishedSite(keyed: false, published: setA);
      h.api.onDeploy = () {
        h.serveDeployed();
        h.reader.absent('availability.json');
      };

      final result = await h.availabilityUseCase(
        target: h.target,
        update: const AvailabilityDelete(),
      );

      expect(result, isA<AvailabilityLive>());
      expect(h.manifestStore.current.entryFor('availability.json'), isNull);
    });

    test('nothing recorded: nothing of ours to delete, whatever the site '
        'holds', () async {
      final h = publishedSite();
      h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));

      final result = await h.availabilityUseCase(
        target: h.target,
        update: const AvailabilityDelete(),
      );

      expect(result, isA<AvailabilityAlreadyPublished>());
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
    });
  });

  group('every other failure is "pending" with a fixed sentence (AV11)', () {
    test('not connected: no Cloudflare call at all', () async {
      final h = publishedSite();
      final target = h.target;
      h.credentials.record = null;

      final result = await h.availabilityUseCase(
        target: target,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.connectionRequired,
      );
      expect(h.api.subdomainReadCalls, 0);
      expect(h.api.workerExistsCalls, 0);
    });

    test('an unreadable connection', () async {
      final h = publishedSite();
      h.credentials.failRead = true;

      final result = await h.availabilityUseCase(
        target: defaultTarget,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.connectionUnreadable,
      );
    });

    test('a connection that no longer describes the target', () async {
      final h = publishedSite();
      final elsewhere = cloudflareTestConnection()
          .selectWorker(CloudflareWorkerName.tryParse('other-library')!)
          .status
          .target!;

      final result = await h.availabilityUseCase(
        target: elsewhere,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.targetMismatch,
      );
      expect(h.api.workerExistsCalls, 0);
    });

    test('offline during the preflight', () async {
      final h = publishedSite();
      h.api.workerExistsError = CloudflareApiException(
        CloudflareApiExceptionKind.network,
      );

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareApiExceptionKind.network.message,
      );
      expect(h.api.deployCalls, 0);
    });

    test('a record the assembler refuses keeps its fixed sentence and sends '
        'nothing', () async {
      // More posters than one Worker version may carry: the assembler's own
      // validation refuses the version before any upload session.
      final h = publishedSite();
      h.manifestStore.current = s8Manifest(
        target: defaultTarget,
        publishId: previousId,
        additional: {
          ...siteExtras,
          'posters/b.jpg': s8File('posters/b.jpg', [7]),
          'posters/c.jpg': s8File('posters/c.jpg', [8]),
        },
        catalogueKeyed: true,
      );

      final result = await h.availabilityUseCase(
        target: h.target,
        update: AvailabilityWrite(setA),
      );

      expect(
        (result as AvailabilityPending).reason,
        CloudflareErrorMessages.artifactInvalid,
      );
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
    });

    test(
      'a thrown upload failure says the live site was not changed',
      () async {
        final h = publishedSite();
        h.api
          ..uploadSessionFactory = dedupAgainst(h.manifestStore.current)
          ..uploadError = CloudflareApiException(
            CloudflareApiExceptionKind.server,
          );

        final result = await h.availabilityUseCase(
          target: h.target,
          update: AvailabilityWrite(setA),
        );

        final reason = (result as AvailabilityPending).reason;
        expect(reason, contains(CloudflareErrorMessages.liveUnchanged));
        expect(reason, contains(CloudflareErrorMessages.uploadedBytesNote));
        expect(h.api.deployCalls, 0);
      },
    );
  });

  test('timings: one "cloudflareAvailability" line with reconcile and the '
      'tail marks, and no library work', () async {
    PublishTimings? captured;
    final h = S8PublishHarness(
      dir,
      workerExists: true,
      manifest: record(),
      timingSink: (t) => captured = t,
    );
    seed(h, siteFiles());
    alreadyVerified(h);

    final result = await h.availabilityUseCase(
      target: h.target,
      update: AvailabilityWrite(setA),
    );
    expect(result, isA<AvailabilityLive>());

    final timings = captured!;
    final stages = timings.marks.map((mark) => mark.stage).toList();
    expect(
      stages,
      containsAllInOrder(<PublishTimingStage>[
        PublishTimingStage.reconcile,
        PublishTimingStage.upload,
        PublishTimingStage.deploy,
        PublishTimingStage.readBack,
      ]),
    );
    expect(stages, isNot(contains(PublishTimingStage.reads)));
    expect(stages, isNot(contains(PublishTimingStage.coverDecisions)));
    expect(stages, isNot(contains(PublishTimingStage.build)));
    final readBack = timings.marks.singleWhere(
      (mark) => mark.stage == PublishTimingStage.readBack,
    );
    expect(readBack.rounds, 1);
    expect(
      timings.describe(),
      startsWith('publish timings cloudflareAvailability: '),
    );
  });

  test('end to end: a catalogue publish keys the site, then the lane '
      'publishes a set and later removes it', () async {
    final h = S8PublishHarness(dir);
    h.reads
      ..books = const [
        CatalogueItem(id: 1, title: 'Lent'),
        CatalogueItem(id: 2, title: 'On the shelf'),
      ]
      ..counts = const {};

    final catalogue = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );
    expect(catalogue, isA<PublishSuccess>());
    final books = h.manifestStore.current.shaFor('books.json');
    expect(h.manifestStore.current.catalogueKeyed, isTrue);

    // Item 1 is lent; the lane sends its key, computed the same way the
    // catalogue publish keyed books.json.
    final key = PublishItemKeys.keyFor(
      salt: utf8.encode('salt-1234567890'),
      itemId: 1,
    );
    h.nextPublishId = 'b' * 32;
    final write = await h.availabilityUseCase(
      target: h.target,
      update: AvailabilityWrite(snapshot([key])),
    );
    expect(write, isA<AvailabilityLive>());
    var current = h.manifestStore.current;
    expect(current.publishId, 'b' * 32);
    expect(current.shaFor('books.json'), books);
    expect(current.catalogueKeyed, isTrue);
    final file = h.artifactStore.bytesByPath['availability.json']!;
    final decoded = jsonDecode(utf8.decode(file)) as Map<String, Object?>;
    expect(decoded['out'], [key]);

    h
      ..nextPublishId = 'c' * 32
      ..api.onDeploy = () {
        h.serveDeployed();
        h.reader.absent('availability.json');
      };
    final removal = await h.availabilityUseCase(
      target: h.target,
      update: const AvailabilityDelete(),
    );
    expect(removal, isA<AvailabilityLive>());
    current = h.manifestStore.current;
    expect(current.publishId, 'c' * 32);
    expect(current.entryFor('availability.json'), isNull);
    expect(current.shaFor('books.json'), books);
    expect(current.catalogueKeyed, isTrue);
    expect(h.api.deployCalls, 3);
  });
}
