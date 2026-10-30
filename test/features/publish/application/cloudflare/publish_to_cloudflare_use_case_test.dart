import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/cloudflare_s8_fakes.dart';

void main() {
  late Directory dir;

  final defaultTarget = cloudflareTestConnection().status.target!;

  /// A connection for the same account at [workerName]/[subdomain].
  CloudflareConnection connectionFor(String workerName, String subdomain) =>
      cloudflareTestConnection()
          .selectSubdomain(
            CloudflareSubdomain.tryParse(subdomain)!,
            confirmed: true,
          )
          // selectWorker is what derives the sealed target from the parts.
          .selectWorker(CloudflareWorkerName.tryParse(workerName)!);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pitaka_s8_publish_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

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

  test(
    'a new catalogue deploy verifies live and commits local state in order',
    () async {
      final h = S8PublishHarness(dir);

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishSuccess>());
      final success = result as PublishSuccess;
      expect(success.pagesLive, isTrue);
      expect(success.localStateSaved, isTrue);
      expect(h.api.deployCalls, 1);
      expect(h.manifestStore.current.state, PublishState.live);
      expect(h.manifestStore.saves.map((m) => m.state), [
        PublishState.deployed,
        PublishState.live,
      ]);
      expect(h.hostStore.stored?.verifiedTarget?.targetId, h.target.targetId);
      expect(h.credentials.record?.status.workersWriteConfirmed, isTrue);
      expect(h.reads.descriptorSites, everyElement(h.target.siteUrl));
      final paths = h.api.uploadManifests.single.map((e) => e.path.value);
      expect(
        paths,
        containsAll(<String>['books.json', 'index.html', 'pitak-publish.json']),
      );
      expect(paths, isNot(contains('events.json')));
    },
  );

  test('unknown state prepares without writes, then confirmation deploys the '
      'reviewed complete snapshot', () async {
    final h = S8PublishHarness(dir, workerExists: true);
    h.reader.body(
      CloudflareLimits.markerPath,
      s8Marker('a' * 32, state: PublishMarkerState.verification),
    );
    h.reads.books = const [CatalogueItem(id: 1, title: 'The Odyssey')];

    final prepared = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(prepared, isA<PublishReplacementRequired>());
    final required = prepared as PublishReplacementRequired;
    expect(required.summary.catalogueItemCount, 1);
    expect(required.summary.posterCount, 0);
    expect(
      required.summary.reason,
      PublishReplacementReason.unknownRemoteState,
    );
    expect(required.summary.remoteAnchor.workerExists, isTrue);
    expect(h.api.uploadManifests, isEmpty);
    expect(h.api.routeUpdates, isEmpty);
    expect(h.api.deployCalls, 0);

    final confirmed = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      confirmation: required.summary,
    );

    expect(confirmed, isA<PublishSuccess>());
    expect((confirmed as PublishSuccess).pagesLive, isTrue);
    expect(h.api.deployCalls, 1);
    final paths = h.api.uploadManifests.single.map((e) => e.path.value);
    expect(paths, containsAll(<String>['events.html', 'events.json']));
  });

  test(
    'changed content after preparation requires a fresh confirmation',
    () async {
      final h = S8PublishHarness(dir, workerExists: true);
      h.reader.body(
        CloudflareLimits.markerPath,
        s8Marker('a' * 32, state: PublishMarkerState.verification),
      );
      h.reads.books = const [CatalogueItem(id: 1, title: 'Before')];
      final first = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );
      final summary = (first as PublishReplacementRequired).summary;

      h.reads.books = const [CatalogueItem(id: 1, title: 'After')];
      final second = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        confirmation: summary,
      );

      expect(second, isA<PublishReplacementRequired>());
      expect(
        (second as PublishReplacementRequired).summary.digest,
        isNot(summary.digest),
      );
      expect(h.api.deployCalls, 0);
      expect(h.api.uploadManifests, isEmpty);
    },
  );

  test('a confirmation is bound to the remote anchor the user reviewed: a '
      'new marker asks again and writes nothing', () async {
    final h = S8PublishHarness(dir, workerExists: true);
    h.reader.body(
      CloudflareLimits.markerPath,
      s8Marker('a' * 32, state: PublishMarkerState.verification),
    );
    final first = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );
    final summary = (first as PublishReplacementRequired).summary;

    // Another device deployed between the review and the confirmation.
    h.reader.body(
      CloudflareLimits.markerPath,
      s8Marker('b' * 32, state: PublishMarkerState.verification),
    );
    final second = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      confirmation: summary,
    );

    expect(second, isA<PublishReplacementRequired>());
    final again = (second as PublishReplacementRequired).summary;
    expect(again.remoteChangedSinceReview, isTrue);
    expect(again.remoteAnchor.publishId, 'b' * 32);
    expect(again.digest, summary.digest, reason: 'only the remote changed');
    expect(h.api.uploadManifests, isEmpty);
    expect(h.api.deployCalls, 0);
    expect(h.manifestStore.saves, isEmpty);
  });

  test('a Worker that vanished after the review also re-prompts', () async {
    final h = S8PublishHarness(dir, workerExists: true);
    h.reader.body(
      CloudflareLimits.markerPath,
      s8Marker('a' * 32, state: PublishMarkerState.verification),
    );
    final first = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );
    final summary = (first as PublishReplacementRequired).summary;

    h.api.workerExistsValue = false;
    h.reader.absent(CloudflareLimits.markerPath);
    final second = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      confirmation: summary,
    );

    expect(second, isA<PublishReplacementRequired>());
    expect(
      (second as PublishReplacementRequired).summary.remoteAnchor.workerExists,
      isFalse,
    );
    expect(h.api.deployCalls, 0);
  });

  test(
    'an unreadable marker after the review re-prompts instead of deploying',
    () async {
      final h = S8PublishHarness(dir, workerExists: true);
      h.reader.body(
        CloudflareLimits.markerPath,
        s8Marker('a' * 32, state: PublishMarkerState.verification),
      );
      final first = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );
      final summary = (first as PublishReplacementRequired).summary;

      h.reader.unreadable(CloudflareLimits.markerPath);
      final second = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        confirmation: summary,
      );

      expect(second, isA<PublishReplacementRequired>());
      final again = (second as PublishReplacementRequired).summary;
      expect(again.remoteAnchor.markerKind, CloudflareMarkerKind.unreadable);
      expect(again.remoteChangedSinceReview, isTrue);
      expect(h.api.deployCalls, 0);
    },
  );

  test(
    'a confirmation for a remote that now matches this phone is stale',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      h.manifestStore.current = s8Manifest(target: h.target, publishId: oldId);
      seed(h, s8CoreFiles(oldId));
      // A foreign marker first: the site is unknown, so a review is offered.
      h.reader.body(
        CloudflareLimits.markerPath,
        s8Marker('b' * 32, state: PublishMarkerState.verification),
      );
      final first = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );
      final summary = (first as PublishReplacementRequired).summary;

      // Then the recorded deployment reappears: nothing needs replacing.
      h.reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
      final second = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        confirmation: summary,
      );

      expect(second, isA<PublishFailure>());
      expect(
        (second as PublishFailure).reason,
        CloudflareErrorMessages.stalePublish,
      );
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    },
  );

  test('a missing-bytes repair whose remote changed re-prompts instead of '
      'dead-ending', () async {
    final oldId = 'a' * 32;
    final h = S8PublishHarness(dir, workerExists: true);
    final previous = s8Manifest(
      target: h.target,
      publishId: oldId,
      additional: {
        'events.html': s8File('events.html', utf8.encode('<html></html>')),
        'events.json': s8File('events.json', utf8.encode('{"posters":[1]}')),
        'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
      },
    );
    h.manifestStore.current = previous;
    alreadyVerified(h);
    h.reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
    final requestedHash = previous.entryFor('posters/a.jpg')!.hash;
    h.api.uploadSessionFactory = (_) => CloudflareUploadSession.tryCreate(
      uploadJwt: 'synthetic-upload-jwt',
      buckets: [
        [requestedHash],
      ],
    )!;

    final first = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );
    final summary = (first as PublishReplacementRequired).summary;
    expect(summary.reason, PublishReplacementReason.localBytesMissing);

    // Another device deployed after the review.
    h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));
    final second = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      confirmation: summary,
    );

    expect(second, isA<PublishReplacementRequired>());
    final again = (second as PublishReplacementRequired).summary;
    expect(again.remoteChangedSinceReview, isTrue);
    // The remote is now a deployment this phone did not make, so the fresh
    // review explains that; the missing bytes still make it a replacement.
    expect(again.reason, PublishReplacementReason.unknownRemoteState);
    expect(h.api.deployCalls, 0);
  });

  group('H1: publishing dead ends', () {
    test('a record for another Worker is a target-changed review, not an '
        'error, and confirming deploys a complete site', () async {
      final h = S8PublishHarness(
        dir,
        connection: connectionFor('other-library', 'library'),
      );
      h.manifestStore.current = s8Manifest(
        target: defaultTarget,
        publishId: 'a' * 32,
      );

      final prepared = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(prepared, isA<PublishReplacementRequired>());
      final summary = (prepared as PublishReplacementRequired).summary;
      expect(summary.reason, PublishReplacementReason.targetChanged);
      expect(summary.previousSiteUrl, defaultTarget.siteUrl);
      expect(h.api.deployCalls, 0);

      final confirmed = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        confirmation: summary,
      );

      expect(confirmed, isA<PublishSuccess>());
      expect(h.api.deployCalls, 1);
      expect(h.manifestStore.current.target?.targetId, h.target.targetId);
      expect(h.hostStore.stored?.verifiedTarget?.targetId, h.target.targetId);
    });

    test('a record for another target never drives an incremental deploy to '
        'an existing Worker', () async {
      final h = S8PublishHarness(
        dir,
        connection: connectionFor('other-library', 'library'),
        workerExists: true,
      );
      h.manifestStore.current = s8Manifest(
        target: defaultTarget,
        publishId: 'a' * 32,
      );
      // The OLD record's marker is live on the destination Worker. If the
      // stale record were used, this would classify as `known` and deploy
      // incrementally.
      h.reader.body(CloudflareLimits.markerPath, s8Marker('a' * 32));

      final prepared = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(prepared, isA<PublishReplacementRequired>());
      expect(
        (prepared as PublishReplacementRequired).summary.reason,
        PublishReplacementReason.targetChanged,
      );
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
    });

    test(
      'the same Worker at a new address is an address-changed review',
      () async {
        final h = S8PublishHarness(
          dir,
          connection: connectionFor('pitak-library', 'newlibrary'),
        );
        h.api.subdomain = cloudflareTestSubdomain('newlibrary');
        h.manifestStore.current = s8Manifest(
          target: defaultTarget,
          publishId: 'a' * 32,
        );

        final prepared = await h.useCase.call(
          target: h.target,
          section: PublishRequestedSection.catalogue,
        );

        expect(prepared, isA<PublishReplacementRequired>());
        final summary = (prepared as PublishReplacementRequired).summary;
        expect(summary.reason, PublishReplacementReason.addressChanged);
        expect(summary.previousSiteUrl, defaultTarget.siteUrl);
        expect(summary.target.siteUrl, contains('newlibrary'));
      },
    );

    test('a deleted Worker gets a recreate review with no writes, and '
        'confirming recreates and verifies the site', () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir);
      h.manifestStore.current = s8Manifest(
        target: h.target,
        publishId: oldId,
        state: PublishState.deployed,
      );

      final prepared = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(prepared, isA<PublishReplacementRequired>());
      final summary = (prepared as PublishReplacementRequired).summary;
      expect(summary.reason, PublishReplacementReason.workerMissing);
      expect(h.api.routeUpdates, isEmpty);
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);

      final confirmed = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        confirmation: summary,
      );

      expect(confirmed, isA<PublishSuccess>());
      expect((confirmed as PublishSuccess).pagesLive, isTrue);
      expect(h.api.deployCalls, 1);
      expect(h.manifestStore.saves.map((m) => m.state), [
        PublishState.deployed,
        PublishState.live,
      ]);
    });

    test(
      'confirming a recreate re-prompts when the Worker reappeared',
      () async {
        final h = S8PublishHarness(dir);
        h.manifestStore.current = s8Manifest(
          target: h.target,
          publishId: 'a' * 32,
          state: PublishState.deployed,
        );
        final prepared = await h.useCase.call(
          target: h.target,
          section: PublishRequestedSection.catalogue,
        );
        final summary = (prepared as PublishReplacementRequired).summary;

        h.api.workerExistsValue = true;
        h.reader.body(
          CloudflareLimits.markerPath,
          s8Marker('b' * 32, state: PublishMarkerState.verification),
        );
        final second = await h.useCase.call(
          target: h.target,
          section: PublishRequestedSection.catalogue,
          confirmation: summary,
        );

        expect(second, isA<PublishReplacementRequired>());
        final again = (second as PublishReplacementRequired).summary;
        expect(again.remoteChangedSinceReview, isTrue);
        expect(again.remoteAnchor.workerExists, isTrue);
        expect(h.api.deployCalls, 0);
      },
    );

    test('retry verification with only another target record says there is '
        'nothing to verify', () async {
      final h = S8PublishHarness(
        dir,
        connection: connectionFor('other-library', 'library'),
      );
      h.manifestStore.current = s8Manifest(
        target: defaultTarget,
        publishId: 'a' * 32,
      );

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        verificationOnly: true,
      );

      expect(result, isA<PublishFailure>());
      expect(
        (result as PublishFailure).reason,
        CloudflareErrorMessages.nothingToVerify,
      );
    });
  });

  group('RH1: a Worker created around the upload session', () {
    test('our own session creating the Worker still deploys', () async {
      final h = S8PublishHarness(dir);
      h.api.onCreateUploadSession = () => h.api.workerExistsValue = true;

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishSuccess>());
      expect(h.api.deployCalls, 1);
    });

    test('a foreign creation before the session stops as stale', () async {
      final h = S8PublishHarness(dir);
      h.api.onWorkerExists = (call) {
        if (call == 2) h.api.workerExistsValue = true;
      };

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      expect(
        (result as PublishFailure).reason,
        CloudflareErrorMessages.stalePublish,
      );
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
    });

    test('a marker appearing after the session stops as stale', () async {
      final h = S8PublishHarness(dir);
      h.api.onCreateUploadSession = () {
        h.reader.body(
          CloudflareLimits.markerPath,
          s8Marker('b' * 32, state: PublishMarkerState.verification),
        );
      };

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      expect(
        (result as PublishFailure).reason,
        CloudflareErrorMessages.stalePublish,
      );
      expect(h.api.deployCalls, 0);
    });

    test('a fresh Worker with an unreadable marker still deploys', () async {
      final h = S8PublishHarness(dir);
      h.api.onCreateUploadSession = () {
        h.api.workerExistsValue = true;
        h.reader.unreadable(CloudflareLimits.markerPath);
      };

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishSuccess>());
      expect(h.api.deployCalls, 1);
    });
  });

  test(
    'verification-only retries an existing deployment without a new deploy',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      h.manifestStore.current = s8Manifest(
        target: h.target,
        publishId: oldId,
        state: PublishState.deployed,
      );
      seed(h, s8CoreFiles(oldId));

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        verificationOnly: true,
      );

      expect(result, isA<PublishSuccess>());
      expect(h.api.deployCalls, 0);
      expect(h.api.uploadManifests, isEmpty);
      expect(h.manifestStore.current.state, PublishState.live);
      expect(h.hostStore.stored?.verifiedTarget?.targetId, h.target.targetId);
    },
  );

  test(
    'failed existing-deployment verification stops without another deploy',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      h.manifestStore.current = s8Manifest(
        target: h.target,
        publishId: oldId,
        state: PublishState.deployed,
      );
      seed(h, s8CoreFiles(oldId));
      h.reader.body('books.json', utf8.encode('different'));

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        verificationOnly: true,
      );

      expect(result, isA<PublishFailure>());
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.current.state, PublishState.deployed);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
    },
  );

  test('an unreachable earlier deployment does not block the publish and is '
      'not marked live', () async {
    final oldId = 'a' * 32;
    final h = S8PublishHarness(dir, workerExists: true);
    h.manifestStore.current = s8Manifest(
      target: h.target,
      publishId: oldId,
      state: PublishState.deployed,
    );
    seed(h, s8CoreFiles(oldId));
    h.reader.unreadable('books.json');

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(result, isA<PublishSuccess>());
    expect(h.api.deployCalls, 1);
    // The first `live` save must come from the NEW deploy's read-back, never
    // from an unproven old record.
    expect(h.manifestStore.saves.map((m) => m.state), [
      PublishState.deployed,
      PublishState.live,
    ]);
  });

  test('an earlier deployment that contradicts this phone offers a '
      'record-contradicted replacement and writes nothing', () async {
    final oldId = 'a' * 32;
    final h = S8PublishHarness(dir, workerExists: true);
    h.manifestStore.current = s8Manifest(
      target: h.target,
      publishId: oldId,
      state: PublishState.deployed,
    );
    seed(h, s8CoreFiles(oldId));
    h.reader.body('books.json', utf8.encode('someone else'));

    final prepared = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(prepared, isA<PublishReplacementRequired>());
    expect(
      (prepared as PublishReplacementRequired).summary.reason,
      PublishReplacementReason.recordContradicted,
    );
    expect(h.api.deployCalls, 0);
    expect(h.api.uploadManifests, isEmpty);
    expect(h.manifestStore.saves, isEmpty);
  });

  test(
    'a failed pre-deploy Version-URL gate stops before upload or deploy',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      h.manifestStore.current = s8Manifest(target: h.target, publishId: oldId);
      h.reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
      h.api.routeError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      expect(h.api.uploadManifests, isEmpty);
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    },
  );

  test('a marker change after upload stops before deployment', () async {
    final oldId = 'a' * 32;
    final h = S8PublishHarness(dir, workerExists: true);
    h.manifestStore.current = s8Manifest(target: h.target, publishId: oldId);
    alreadyVerified(h);
    h.reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
    h.api.onCreateUploadSession = () {
      h.reader.body(CloudflareLimits.markerPath, s8Marker('b' * 32));
    };

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(result, isA<PublishFailure>());
    expect(
      (result as PublishFailure).reason,
      CloudflareErrorMessages.stalePublish,
    );
    expect(h.api.deployCalls, 0);
    expect(h.manifestStore.saves, isEmpty);
  });

  test('a server-requested carried hash with no bytes enters replacement '
      'instead of deploying an incomplete Worker', () async {
    final oldId = 'a' * 32;
    final h = S8PublishHarness(dir, workerExists: true);
    final previous = s8Manifest(
      target: h.target,
      publishId: oldId,
      additional: {
        'events.html': s8File('events.html', utf8.encode('<html></html>')),
        'events.json': s8File('events.json', utf8.encode('{"posters":[1]}')),
        'posters/a.jpg': s8File('posters/a.jpg', [1, 2, 3]),
      },
    );
    h.manifestStore.current = previous;
    alreadyVerified(h);
    h.reader.body(CloudflareLimits.markerPath, s8Marker(oldId));
    final requestedHash = previous.entryFor('posters/a.jpg')!.hash;
    h.api.uploadSessionFactory = (_) => CloudflareUploadSession.tryCreate(
      uploadJwt: 'synthetic-upload-jwt',
      buckets: [
        [requestedHash],
      ],
    )!;

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(result, isA<PublishReplacementRequired>());
    final summary = (result as PublishReplacementRequired).summary;
    expect(summary.reason, PublishReplacementReason.localBytesMissing);
    expect(h.api.bucketCalls, 0);
    expect(h.api.deployCalls, 0);

    // N1 regression: the offered repair must be CONFIRMABLE and deploy once.
    // The scripted session asked for the OLD poster hash; a real session asks
    // for the new manifest's hashes, and the repair carries none of them.
    h.api.uploadSessionFactory = null;
    final confirmed = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      confirmation: summary,
    );
    expect(confirmed, isA<PublishSuccess>());
    expect((confirmed as PublishSuccess).pagesLive, isTrue);
    expect(h.api.deployCalls, 1);
    expect(h.manifestStore.current.state, PublishState.live);
  });

  test('J.7 regression: a multi-bucket upload deploys with the token from the '
      'final bucket only', () async {
    final h = S8PublishHarness(dir);
    h.api.uploadSessionFactory = cloudflareOneBucketPerHashSession;

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(result, isA<PublishSuccess>());
    expect((result as PublishSuccess).pagesLive, isTrue);
    final requested = h.api.uploadManifests.single
        .map((entry) => entry.hash)
        .toSet();
    expect(requested.length, greaterThan(1), reason: 'needs several buckets');
    expect(h.api.bucketCalls, requested.length);
    expect(
      h.api.bucketUploads.map((bucket) => bucket.single.hash),
      orderedEquals(requested),
      reason: 'buckets upload in the order Cloudflare requested them',
    );
    expect(h.api.deployCalls, 1);
    expect(h.api.deployedCompletionTokens, [
      h.api.completionToken.use((value) => value),
    ]);
    expect(h.manifestStore.current.state, PublishState.live);
  });

  test(
    'a final bucket without a completion token stops before deployment',
    () async {
      final h = S8PublishHarness(dir);
      h.api
        ..uploadSessionFactory = cloudflareOneBucketPerHashSession
        ..issueCompletionToken = false;

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      final reason = (result as PublishFailure).reason;
      expect(reason, contains(CloudflareErrorMessages.uploadNotConfirmed));
      expect(reason, contains(CloudflareErrorMessages.uploadedBytesNote));
      expect(reason, isNot(contains('synthetic-upload-jwt')));
      expect(h.api.bucketCalls, greaterThan(1));
      expect(h.api.deployCalls, 0);
      expect(h.api.routeUpdates, isEmpty, reason: 'no post-deploy route write');
      expect(h.manifestStore.saves, isEmpty);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
    },
  );

  test(
    'a stalled upload shows the stall copy and never deploys (H2)',
    () async {
      final h = S8PublishHarness(dir);
      h.api
        ..uploadSessionFactory = cloudflareOneBucketPerHashSession
        ..uploadError = CloudflareApiException(
          CloudflareApiExceptionKind.uploadStalled,
        );

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      final reason = (result as PublishFailure).reason;
      expect(
        reason,
        contains(CloudflareApiExceptionKind.uploadStalled.message),
      );
      expect(reason, contains(CloudflareErrorMessages.liveUnchanged));
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
    },
  );

  test(
    'a too-slow upload shows the too-slow copy and never deploys (H2)',
    () async {
      final h = S8PublishHarness(dir);
      h.api
        ..uploadSessionFactory = cloudflareOneBucketPerHashSession
        ..uploadError = CloudflareApiException(
          CloudflareApiExceptionKind.uploadTooSlow,
        );

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      final reason = (result as PublishFailure).reason;
      expect(
        reason,
        contains(CloudflareApiExceptionKind.uploadTooSlow.message),
      );
      expect(reason, contains('Wi-Fi'));
      expect(h.api.deployCalls, 0);
      expect(h.manifestStore.saves, isEmpty);
    },
  );

  test('unverified deploy stays deployed, then exact-marker retry avoids a '
      'second deployment', () async {
    final h = S8PublishHarness(dir)..autoServe = false;

    final first = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(first, isA<PublishSuccess>());
    expect((first as PublishSuccess).pagesLive, isNull);
    expect(h.manifestStore.current.state, PublishState.deployed);
    expect(h.hostStore.stored?.verifiedTarget, isNull);
    expect(h.api.deployCalls, 1);

    h.serveDeployed();
    final retry = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
      verificationOnly: true,
    );

    expect(retry, isA<PublishSuccess>());
    expect((retry as PublishSuccess).pagesLive, isTrue);
    expect(h.api.deployCalls, 1);
    expect(h.manifestStore.current.state, PublishState.live);
  });

  test(
    'a failed live save cannot advance the journal or connection flag',
    () async {
      final h = S8PublishHarness(dir);
      h.manifestStore.failLiveSave = true;

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishSuccess>());
      expect((result as PublishSuccess).localStateSaved, isFalse);
      expect(h.manifestStore.current.state, PublishState.deployed);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
      expect(h.credentials.record?.status.workersWriteConfirmed, isFalse);
    },
  );

  test(
    'ordinary events preserve the catalogue and return the events URL',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      final previous = s8Manifest(target: h.target, publishId: oldId);
      h.manifestStore.current = previous;
      alreadyVerified(h);
      seed(h, s8CoreFiles(oldId));

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.events,
      );

      expect(result, isA<PublishSuccess>());
      expect(
        (result as PublishSuccess).pagesUrl,
        '${h.target.siteUrl}events.html',
      );
      expect(
        h.manifestStore.current.shaFor('books.json'),
        previous.shaFor('books.json'),
      );
      expect(h.manifestStore.current.entryFor('events.json'), isNotNull);
      expect(h.api.deployCalls, 1);
    },
  );

  test(
    'a live manifest with incomplete local state is re-proven before repair',
    () async {
      final oldId = 'a' * 32;
      final h = S8PublishHarness(dir, workerExists: true);
      h.manifestStore.current = s8Manifest(target: h.target, publishId: oldId);
      seed(h, s8CoreFiles(oldId));

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
        verificationOnly: true,
      );

      expect(result, isA<PublishSuccess>());
      expect(h.api.deployCalls, 0);
      expect(h.hostStore.stored?.verifiedTarget?.targetId, h.target.targetId);
    },
  );

  test('events cannot create a new site before the catalogue', () async {
    final h = S8PublishHarness(dir);

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.events,
    );

    expect(result, isA<PublishFailure>());
    expect(
      (result as PublishFailure).reason,
      CloudflareErrorMessages.catalogueFirst,
    );
    expect(h.api.uploadManifests, isEmpty);
    expect(h.api.deployCalls, 0);
  });

  test(
    'post-deploy privacy failure is explicit and remains unverified',
    () async {
      final h = S8PublishHarness(dir);
      h.api.onDeploy = () {
        h.serveDeployed();
        h.api.routeError = CloudflareApiException(
          CloudflareApiExceptionKind.forbidden,
        );
      };

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      expect(
        (result as PublishFailure).reason,
        contains(CloudflareErrorMessages.versionUrlPrivacy),
      );
      expect(h.manifestStore.current.state, PublishState.deployed);
      expect(h.hostStore.stored?.verifiedTarget, isNull);
    },
  );

  test(
    'API failures never include token, JWT, or raw response material',
    () async {
      final h = S8PublishHarness(dir);
      h.api.sessionError = CloudflareApiException(
        CloudflareApiExceptionKind.server,
      );

      final result = await h.useCase.call(
        target: h.target,
        section: PublishRequestedSection.catalogue,
      );

      expect(result, isA<PublishFailure>());
      final reason = (result as PublishFailure).reason;
      expect(reason, isNot(contains('cfut_')));
      expect(reason, isNot(contains('synthetic-upload-jwt')));
      expect(reason, contains(CloudflareErrorMessages.liveUnchanged));
    },
  );

  test('the debug-only API diagnostic names the stage and codes, never '
      'secrets or addresses', () async {
    // appLog routes through debugPrint in debug/test builds only; capture it.
    final printed = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    addTearDown(() => debugPrint = previous);
    final h = S8PublishHarness(dir);
    h.api.sessionError = CloudflareApiException(
      CloudflareApiExceptionKind.requestRejected,
      statusCode: 400,
      errorCodes: const [10021],
    );

    final result = await h.useCase.call(
      target: h.target,
      section: PublishRequestedSection.catalogue,
    );

    expect(result, isA<PublishFailure>());
    final line = printed.single;
    expect(line, startsWith('CloudflarePublish API failure: requestRejected'));
    expect(line, contains('status=400'));
    expect(line, contains('codes=[10021]'));
    expect(line, contains('deployStarted=false'));
    expect(line, contains('createUploadSession'), reason: 'the stack names it');
    expect(line, isNot(contains('cfut_')));
    expect(line, isNot(contains('synthetic-upload-jwt')));
    expect(line, isNot(contains(h.target.siteUrl)));
    expect(line, isNot(contains(h.target.accountId.value)));
  });
}
