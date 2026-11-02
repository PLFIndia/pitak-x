import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/publish_availability_use_case.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../support/github_lane_fakes.dart';

/// The GitHub availability publish (plan S4, ADR 0019 Decisions 7 and 10):
/// one file, `deployed` with its proof, no Pages wait inside the queue, gate
/// 7b, and "pending" — never a retry loop — for every failure.
void main() {
  final target = GitHubPublishTarget.create('me/lib')!;
  const clock = 120000;

  AvailabilitySnapshot snapshot(List<String> keys) =>
      AvailabilitySnapshot.tryCreate(keys: keys, asOfMillis: 61000)!;
  final twoOut = snapshot(['00000000000000aa', '00000000000000bb']);
  final twoOutBytes = encodeAvailabilityJsonBytes(AvailabilityDocument(twoOut));

  /// This phone's live, keyed catalogue on me/lib — the lane's normal start.
  PublishManifest keyedLive({Map<String, String> extra = const {}}) =>
      PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'HEAD',
        ownershipConfirmed: true,
        state: PublishState.live,
        fileShas: {
          'books.json': 'keyed-books',
          'index.html': 'viewer',
          'events.json': 'events',
          ...extra,
        },
        coverUrlByBookId: const {'1': 'covers/a.jpg'},
        proofPath: PublishProofPath.booksJson,
        catalogueKeyed: true,
      );

  ({
    PublishAvailabilityUseCase useCase,
    LaneGitHub api,
    LaneMemManifest manifest,
    LaneRecorder recorder,
    LaneSite site,
  })
  harness({
    PublishManifest? record,
    Map<String, String>? tree,
    String? token = 'TKN',
    PublishTimingSink? timingSink,
  }) {
    final local = record ?? keyedLive();
    // R6: the remote starts as what this phone recorded, unless a test says
    // otherwise.
    final api = LaneGitHub(
      tree: tree ?? local.fileShas,
      head: local.headSha ?? 'HEAD',
    );
    final manifest = LaneMemManifest(local);
    final recorder = LaneRecorder();
    final site = LaneSite();
    return (
      useCase: PublishAvailabilityUseCase(
        api: api,
        credentials: LaneCredentials(signedInToken: token),
        manifest: manifest,
        hostState: recorder,
        reader: site,
        sleep: (_) async {},
        clock: () => clock,
        timingSink: timingSink,
      ),
      api: api,
      manifest: manifest,
      recorder: recorder,
      site: site,
    );
  }

  Future<AvailabilityPublishResult> write(
    PublishAvailabilityUseCase useCase, [
    AvailabilitySnapshot? set,
  ]) => useCase(target: target, update: AvailabilityWrite(set ?? twoOut));

  Future<AvailabilityPublishResult> remove(
    PublishAvailabilityUseCase useCase,
  ) => useCase(target: target, update: const AvailabilityDelete());

  group('a write', () {
    test('commits exactly availability.json against the head it read, and '
        'saves the record deployed with its proof', () async {
      final h = harness();

      final result = await write(h.useCase);

      expect(result, isA<AvailabilityGoingLive>());
      final commit = h.api.commits.single;
      expect(commit.head, 'HEAD', reason: 'expectedHead = the head read');
      expect(commit.deleted, isEmpty);
      final file = commit.files.single;
      expect(file.path, 'availability.json');
      expect(file.upload, isTrue);
      expect(file.bytes, twoOutBytes);
      expect(
        utf8.decode(file.bytes),
        '{"schemaVersion":1,"asOf":60000,'
        '"out":["00000000000000aa","00000000000000bb"]}',
      );

      final record = h.manifest.current;
      expect(record.state, PublishState.deployed);
      expect(record.headSha, 'commit-1');
      expect(record.proofPath, PublishProofPath.availabilityJson);
      expect(record.shaFor('availability.json'), laneSha(twoOutBytes));
      // Every other app-owned file survives; the catalogue stays keyed.
      expect(record.shaFor('books.json'), 'keyed-books');
      expect(record.shaFor('events.json'), 'events');
      expect(record.catalogueKeyed, isTrue);
      expect(record.coverSourceFor('1'), 'covers/a.jpg');
    });

    test('returns "going live" with the request the deferred check needs; '
        'Pages is not polled inside the queue', () async {
      final h = harness();

      final result = await write(h.useCase) as AvailabilityGoingLive;

      expect(result.acceptedAt, clock);
      expect(result.localStateSaved, isTrue);
      final request = result.verification!;
      expect(request.headSha, 'commit-1');
      expect(request.proof, PublishProofPath.availabilityJson);
      expect(request.expectedSha, laneSha(twoOutBytes));
      expect(request.describes(h.manifest.current), isTrue);
      expect(h.site.reads, isEmpty, reason: 'no read-back inside the queue');
      expect(h.recorder.recorded, isEmpty, reason: 'not proven yet');
    });

    test('an unchanged set commits nothing (no Pages build spent)', () async {
      final h = harness(
        record: keyedLive(extra: {'availability.json': laneSha(twoOutBytes)}),
      );

      // The branch already holds exactly these bytes. (Whether a set with a
      // newer asOf is worth sending at all is the lane's decision, by
      // content hash; this use case compares the file itself.)
      expect(await write(h.useCase), isA<AvailabilityAlreadyPublished>());
      expect(h.api.commits, isEmpty);
      expect(h.manifest.saves, isEmpty);
    });

    test('a changed set replaces the recorded file', () async {
      final h = harness(
        record: keyedLive(extra: {'availability.json': laneSha(twoOutBytes)}),
      );

      final oneOut = snapshot(['00000000000000aa']);
      expect(await write(h.useCase, oneOut), isA<AvailabilityGoingLive>());
      expect(h.api.commits.single.files.single.upload, isTrue);
      expect(
        h.manifest.current.shaFor('availability.json'),
        laneSha(encodeAvailabilityJsonBytes(AvailabilityDocument(oneOut))),
      );
    });

    test('an empty set is published as a real answer', () async {
      final h = harness();
      final none = snapshot(const []);

      expect(await write(h.useCase, none), isA<AvailabilityGoingLive>());
      expect(
        utf8.decode(h.api.commits.single.files.single.bytes),
        '{"schemaVersion":1,"asOf":60000,"out":[]}',
      );
    });
  });

  group("gate 7b: the live books.json is this phone's own keyed publish", () {
    test('an unkeyed record: not ready, nothing read or written', () async {
      final h = harness(
        record: const PublishManifest(
          repo: 'me/lib',
          branch: 'main',
          headSha: 'HEAD',
          state: PublishState.live,
          fileShas: {'books.json': 'old-books'},
        ),
      );

      final result = await write(h.useCase);

      expect(
        (result as AvailabilityNotReady).reason,
        AvailabilityPublishMessages.catalogueNotKeyed,
      );
      expect(h.api.commits, isEmpty);
      expect(h.site.reads, isEmpty);
      expect(h.manifest.saves, isEmpty);
    });

    test("another writer's books.json on the branch clears the flag "
        '(another phone or an older Pitak)', () async {
      final h = harness(
        tree: {...keyedLive().fileShas, 'books.json': 'someone-else'},
      );

      final result = await write(h.useCase) as AvailabilityNotReady;
      expect(h.api.commits, isEmpty);
      expect(result.staleFileRecorded, isFalse, reason: 'no file recorded');
    });

    test('a recorded file that the live books.json no longer vouches for is '
        'reported, so the lane removes it (plan S6)', () async {
      final record = keyedLive(
        extra: {'availability.json': laneSha(twoOutBytes)},
      );
      final h = harness(
        record: record,
        tree: {...record.fileShas, 'books.json': 'someone-else'},
      );

      final result = await write(h.useCase) as AvailabilityNotReady;

      expect(result.staleFileRecorded, isTrue);
      expect(h.api.commits, isEmpty, reason: 'the use case itself sends none');
    });

    test('a record of another repository never counts', () async {
      final h = harness(
        record: keyedLive().reconciledFrom(
          tree: GitHubTreeSnapshot(
            repo: 'me/other',
            branch: 'main',
            headSha: 'HEAD',
            files: keyedLive().fileShas,
            truncated: false,
          ),
          ownerRepo: 'me/other',
          branch: 'main',
        ),
        tree: keyedLive().fileShas,
      );

      expect(await write(h.useCase), isA<AvailabilityNotReady>());
    });
  });

  group('a removal (the switch is off)', () {
    test(
      'deletes exactly the recorded file and records the absence proof',
      () async {
        final h = harness(
          record: keyedLive(extra: {'availability.json': laneSha(twoOutBytes)}),
        );

        final result = await remove(h.useCase) as AvailabilityGoingLive;

        final commit = h.api.commits.single;
        expect(commit.files, isEmpty);
        expect(commit.deleted, ['availability.json']);
        final record = h.manifest.current;
        expect(record.shaFor('availability.json'), isNull);
        expect(record.proofPath, PublishProofPath.availabilityJsonAbsent);
        expect(record.catalogueKeyed, isTrue);
        expect(
          result.verification!.proof,
          PublishProofPath.availabilityJsonAbsent,
        );
        expect(result.verification!.expectedSha, isNull);
      },
    );

    test('needs no gate: deleting is always the safe direction', () async {
      // The catalogue is no longer this phone's keyed publish, so the file's
      // keys may match nothing: removing it is exactly right.
      final h = harness(
        record: keyedLive(extra: {'availability.json': 'a'}),
        tree: {
          ...keyedLive().fileShas,
          'books.json': 'someone-else',
          'availability.json': 'a',
        },
      );

      expect(await remove(h.useCase), isA<AvailabilityGoingLive>());
      expect(h.api.commits.single.deleted, ['availability.json']);
    });

    test('nothing recorded: nothing to delete, no commit', () async {
      final h = harness();

      expect(await remove(h.useCase), isA<AvailabilityAlreadyPublished>());
      expect(h.api.commits, isEmpty);
    });

    test('a file this phone never wrote is not ours to delete (R13)', () async {
      final h = harness(
        tree: {...keyedLive().fileShas, 'availability.json': 'humans-file'},
      );

      expect(await remove(h.useCase), isA<AvailabilityAlreadyPublished>());
      expect(h.api.commits, isEmpty);
    });

    test('a file already gone from the branch: nothing to delete', () async {
      final h = harness(
        record: keyedLive(extra: {'availability.json': 'a'}),
        tree: keyedLive().fileShas,
      );

      expect(await remove(h.useCase), isA<AvailabilityAlreadyPublished>());
      expect(h.api.commits, isEmpty);
    });
  });

  group('every failure is "pending" with a fixed message (AV11)', () {
    test('not signed in: no GitHub call at all', () async {
      final h = harness(token: null);

      expect(
        (await write(h.useCase) as AvailabilityPending).reason,
        'Not signed in to GitHub.',
      );
      expect(h.api.commits, isEmpty);
    });

    test('Pages off, or Pages unreachable', () async {
      final off = harness()..api.pages = null;
      expect(
        (await write(off.useCase) as AvailabilityPending).reason,
        gitHubPagesNotServingMessage,
      );

      final workflow = harness()
        ..api.pages = const PagesSite(
          sourceBranch: 'main',
          sourcePath: '/',
          isWorkflowBuild: true,
        );
      expect(
        (await write(workflow.useCase) as AvailabilityPending).reason,
        gitHubPagesNotServingMessage,
      );

      final unreachable = harness()..api.throwOnPages = true;
      expect(
        (await write(unreachable.useCase) as AvailabilityPending).reason,
        gitHubNetworkErrorMessage,
      );
    });

    test('an unreadable or truncated tree writes nothing', () async {
      final unreadable = harness()..api.throwOnTree = true;
      expect(
        (await write(unreadable.useCase) as AvailabilityPending).reason,
        gitHubSiteStateUnreadableMessage,
      );

      final truncated = harness()..api.truncated = true;
      expect(
        (await write(truncated.useCase) as AvailabilityPending).reason,
        gitHubTreeTooLargeMessage,
      );
      expect(unreadable.api.commits, isEmpty);
      expect(truncated.api.commits, isEmpty);
    });

    test(
      'a stale head: pending "will retry", nothing saved, no retry here',
      () async {
        final h = harness()..api.forcedResult = const PublishCommitStale();

        final result = await write(h.useCase);

        expect(
          (result as AvailabilityPending).reason,
          AvailabilityPublishMessages.siteMovedOn,
        );
        expect(h.api.commits, hasLength(1), reason: 'never an immediate retry');
        expect(h.manifest.saves, isEmpty);
      },
    );

    test('an HTTP error keeps its fixed message; a thrown commit is a '
        'network error', () async {
      final refused = harness()
        ..api.forcedResult = const PublishCommitHttpError(403, 'injected body');
      final reason =
          (await write(refused.useCase) as AvailabilityPending).reason;
      expect(reason, gitHubHttpErrorMessage(403));
      expect(reason, isNot(contains('injected')));

      final thrown = harness()..api.throwOnCommit = true;
      expect(
        (await write(thrown.useCase) as AvailabilityPending).reason,
        gitHubNetworkErrorMessage,
      );
      expect(refused.manifest.saves, isEmpty);
      expect(thrown.manifest.saves, isEmpty);
    });

    test('a record that cannot be saved: going live, but nothing for the '
        'deferred check to upgrade (R9)', () async {
      final h = harness()..manifest.saveFails = true;

      final result = await write(h.useCase) as AvailabilityGoingLive;

      expect(result.localStateSaved, isFalse);
      expect(result.verification, isNull);
      expect(h.api.commits, hasLength(1), reason: 'the site IS updated');
    });
  });

  group('the pre-check of an unconfirmed earlier commit', () {
    PublishManifest unconfirmedAvailability() => PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'HEAD',
      ownershipConfirmed: true,
      fileShas: {
        ...keyedLive().fileShas,
        'availability.json': laneSha(twoOutBytes),
      },
      proofPath: PublishProofPath.availabilityJson,
      catalogueKeyed: true,
    );

    test(
      'reads ITS proof; a match marks it live before the new commit',
      () async {
        final h = harness(record: unconfirmedAvailability());
        h.site.answer = (path, _) => path == 'availability.json'
            ? laneBody(twoOutBytes)
            : const PublishedSiteReadUnreadable();

        final next = snapshot(['00000000000000cc']);
        expect(await write(h.useCase, next), isA<AvailabilityGoingLive>());

        expect(h.site.reads.single.$1, 'availability.json');
        expect(h.manifest.saves.first.state, PublishState.live);
        expect(h.manifest.saves.first.headSha, 'HEAD');
        expect(h.recorder.recorded, hasLength(1));
        expect(h.manifest.current.state, PublishState.deployed);
        expect(h.manifest.current.headSha, 'commit-1');
      },
    );

    test('a contradiction stops the publish', () async {
      final h = harness(record: unconfirmedAvailability());
      h.site.answer = (_, _) => laneBody(utf8.encode('{"edited":"by hand"}'));

      final result = await write(h.useCase, snapshot(['00000000000000cc']));

      expect(
        (result as AvailabilityPending).reason,
        gitHubSiteChangedSincePublishMessage,
      );
      expect(h.api.commits, isEmpty);
    });

    test('an unreachable site does not block the lane', () async {
      final h = harness(record: unconfirmedAvailability());

      expect(
        await write(h.useCase, snapshot(['00000000000000cc'])),
        isA<AvailabilityGoingLive>(),
      );
    });
  });

  test('timings: one "availability" line with reconcile and commit, numbers '
      'only (plan S0 sink, used by S8)', () async {
    final lines = <PublishTimings>[];
    final h = harness(timingSink: lines.add);

    await write(h.useCase);

    final timings = lines.single;
    expect(timings.operation, 'availability');
    expect(timings.markFor(PublishTimingStage.reconcile), isNotNull);
    expect(
      timings.markFor(PublishTimingStage.commit)!.bytes,
      twoOutBytes.length,
    );
    expect(timings.markFor(PublishTimingStage.readBack), isNull);
  });

  group('end to end against fakes: publish, then the deferred check', () {
    test('the lane commits, the queue is free, and the check proves it live '
        'once Pages serves the new bytes', () async {
      final h = harness();
      final queue = SerialOpQueue();

      final result =
          await queue.enqueue(() => write(h.useCase)) as AvailabilityGoingLive;

      // Pages: the old state (no file yet: a 404) for two reads, then the
      // committed file.
      h.site.answer = (path, read) {
        if (read < 2) return const PublishedSiteReadAbsent();
        final sha = h.api.tree[path];
        return sha == laneSha(twoOutBytes)
            ? laneBody(twoOutBytes)
            : const PublishedSiteReadUnreadable();
      };
      final outcome = await DeferredPublishVerification(
        reader: h.site,
        manifest: h.manifest,
        hostState: h.recorder,
        queue: queue,
        sleep: (_) async {},
      ).run(result.verification!);

      expect(outcome, DeferredVerificationOutcome.live);
      expect(h.manifest.current.state, PublishState.live);
      expect(h.manifest.current.headSha, 'commit-1');
      expect(h.recorder.recorded.single.targetId, target.targetId);
    });

    test('the next update builds on the last commit, and the removal after '
        'it is proven by a 404', () async {
      final h = harness();
      final queue = SerialOpQueue();
      DeferredPublishVerification check() => DeferredPublishVerification(
        reader: h.site,
        manifest: h.manifest,
        hostState: h.recorder,
        queue: queue,
        sleep: (_) async {},
      );
      // Pages serves exactly what the branch holds.
      h.site.answer = (path, _) {
        final sha = h.api.tree[path];
        if (sha == null) return const PublishedSiteReadAbsent();
        return sha == laneSha(twoOutBytes)
            ? laneBody(twoOutBytes)
            : const PublishedSiteReadUnreadable();
      };

      final first = await write(h.useCase) as AvailabilityGoingLive;
      expect(
        await check().run(first.verification!),
        DeferredVerificationOutcome.live,
      );

      final removal = await remove(h.useCase) as AvailabilityGoingLive;
      expect(h.api.commits.last.head, 'commit-1');
      expect(
        await check().run(removal.verification!),
        DeferredVerificationOutcome.live,
      );
      expect(h.manifest.current.headSha, 'commit-2');
      expect(h.manifest.current.shaFor('availability.json'), isNull);
      expect(h.manifest.current.catalogueKeyed, isTrue);
    });

    test('a newer commit before the proof: the check is superseded and '
        'never marks the newer record live', () async {
      final h = harness();
      final first = await write(h.useCase) as AvailabilityGoingLive;
      await write(h.useCase, snapshot(['00000000000000cc']));
      h.site.answer = (_, _) => laneBody(twoOutBytes);

      final outcome = await DeferredPublishVerification(
        reader: h.site,
        manifest: h.manifest,
        hostState: h.recorder,
        queue: SerialOpQueue(),
        sleep: (_) async {},
      ).run(first.verification!);

      expect(outcome, DeferredVerificationOutcome.superseded);
      expect(h.manifest.current.headSha, 'commit-2');
      expect(h.manifest.current.state, PublishState.deployed);
      expect(h.recorder.recorded, isEmpty);
    });
  });
}
