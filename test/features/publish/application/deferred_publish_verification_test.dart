import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../support/github_lane_fakes.dart';

/// SPECIFICATION of the deferred check (ADR 0019 Decision 10, plan A.6 #21).
///
/// What these tests pin: it polls until the expected state appears (old bytes
/// and a 404 on a first publish mean "keep waiting", never "contradicted"),
/// a removal is proven by an exact 404, running out of budget leaves the
/// record `deployed`, and only an unchanged `deployed` record is upgraded.
void main() {
  final target = GitHubPublishTarget.create('me/lib')!;
  final newBytes = utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}');
  final oldBytes = utf8.encode('{"schemaVersion":1,"asOf":0,"out":["x"]}');
  const absent = PublishedSiteReadAbsent();
  const unreadable = PublishedSiteReadUnreadable();

  /// The record right after an availability commit.
  PublishManifest written({String head = 'commit-1'}) => PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: head,
    ownershipConfirmed: true,
    fileShas: {'books.json': 'b', 'availability.json': laneSha(newBytes)},
    proofPath: PublishProofPath.availabilityJson,
    catalogueKeyed: true,
  );

  /// The record right after an availability removal.
  PublishManifest removed() => const PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'commit-1',
    ownershipConfirmed: true,
    fileShas: {'books.json': 'b'},
    proofPath: PublishProofPath.availabilityJsonAbsent,
  );

  DeferredVerificationRequest requestFor(PublishManifest record) =>
      DeferredVerificationRequest.forRecord(
        target: target,
        record: record,
        revision: 7,
      )!;

  ({
    DeferredPublishVerification check,
    LaneMemManifest manifest,
    LaneRecorder recorder,
    List<Duration> sleeps,
  })
  harness(
    PublishManifest record,
    LaneSite site, {
    SerialOpQueue? queue,
    void Function(int sleep)? onSleep,
  }) {
    final manifest = LaneMemManifest(record);
    final recorder = LaneRecorder();
    final sleeps = <Duration>[];
    final check = DeferredPublishVerification(
      reader: site,
      manifest: manifest,
      hostState: recorder,
      queue: queue ?? SerialOpQueue(),
      sleep: (duration) async {
        sleeps.add(duration);
        onSleep?.call(sleeps.length);
      },
    );
    return (
      check: check,
      manifest: manifest,
      recorder: recorder,
      sleeps: sleeps,
    );
  }

  group('DeferredVerificationRequest.forRecord', () {
    test('a deployed record with a file proof carries its hash', () {
      final request = requestFor(written());
      expect(request.headSha, 'commit-1');
      expect(request.proof, PublishProofPath.availabilityJson);
      expect(request.expectedSha, laneSha(newBytes));
      expect(request.describes(written()), isTrue);
    });

    test('an absence proof carries no hash', () {
      final request = requestFor(removed());
      expect(request.expectedSha, isNull);
      expect(request.isProvenBy(absent), isTrue);
      expect(request.isProvenBy(laneBody(newBytes)), isFalse);
    });

    test('nothing to prove: live, no head, no proof, other repo, or a file '
        'proof without a recorded hash', () {
      final cases = <String, PublishManifest>{
        'live': written().asLive(),
        'no head': const PublishManifest(
          repo: 'me/lib',
          branch: 'main',
          fileShas: {'availability.json': 'a'},
          proofPath: PublishProofPath.availabilityJson,
        ),
        'no proof': const PublishManifest(
          repo: 'me/lib',
          branch: 'main',
          headSha: 'c',
          fileShas: {'books.json': 'b'},
        ),
        'other repo': const PublishManifest(
          repo: 'me/other',
          branch: 'main',
          headSha: 'c',
          fileShas: {'availability.json': 'a'},
          proofPath: PublishProofPath.availabilityJson,
        ),
        'file proof, no hash': const PublishManifest(
          repo: 'me/lib',
          branch: 'main',
          headSha: 'c',
          fileShas: {'books.json': 'b'},
          proofPath: PublishProofPath.availabilityJson,
        ),
      };
      for (final MapEntry(key: name, value: record) in cases.entries) {
        expect(
          DeferredVerificationRequest.forRecord(
            target: target,
            record: record,
            revision: 1,
          ),
          isNull,
          reason: name,
        );
      }
    });

    test('toString names only the proof (no hashes, no addresses)', () {
      expect(
        requestFor(written()).toString(),
        'DeferredVerificationRequest(availabilityJson)',
      );
    });
  });

  group('the budget (ReadBackBudget)', () {
    test('first read at 30 s, then every 10 s, last read at 150 s', () {
      expect(ReadBackBudget.deferredFirstDelay, const Duration(seconds: 30));
      expect(ReadBackBudget.deferredInterval, const Duration(seconds: 10));
      expect(ReadBackBudget.deferredTotal, const Duration(seconds: 150));
      expect(ReadBackBudget.deferredAttempts, 13);
    });

    test('runs on real timers exactly at those times (fake_async)', () {
      fakeAsync((async) {
        final site = LaneSite((_, _) => unreadable);
        final check = DeferredPublishVerification(
          reader: site,
          manifest: LaneMemManifest(written()),
          hostState: LaneRecorder(),
          queue: SerialOpQueue(),
        );
        DeferredVerificationOutcome? outcome;
        unawaited(check.run(requestFor(written())).then((o) => outcome = o));

        async.elapse(const Duration(seconds: 29));
        expect(site.reads, isEmpty, reason: 'nothing before 30 s');
        async.elapse(const Duration(seconds: 1));
        expect(site.reads, hasLength(1));
        async.elapse(const Duration(seconds: 10));
        expect(site.reads, hasLength(2));
        async.elapse(const Duration(seconds: 110));
        expect(site.reads, hasLength(13));
        expect(outcome, DeferredVerificationOutcome.notProven);
        async.elapse(const Duration(minutes: 5));
        expect(site.reads, hasLength(13), reason: 'it stops at 150 s');
      });
    });
  });

  group('polls until the expected state', () {
    test('old bytes, then the committed bytes: live, and the address is '
        'recorded', () async {
      final site = LaneSite(
        (_, read) => read < 3 ? laneBody(oldBytes) : laneBody(newBytes),
      );
      final h = harness(written(), site);

      final outcome = await h.check.run(requestFor(written()));

      expect(outcome, DeferredVerificationOutcome.live);
      expect(site.reads, hasLength(4));
      expect(h.manifest.current.state, PublishState.live);
      expect(h.manifest.current.headSha, 'commit-1');
      expect(h.recorder.recorded.single.targetId, target.targetId);
      expect(h.sleeps, [
        ReadBackBudget.deferredFirstDelay,
        ReadBackBudget.deferredInterval,
        ReadBackBudget.deferredInterval,
        ReadBackBudget.deferredInterval,
      ]);
    });

    test('reads the proof file with its reader cap and a fresh cache-buster '
        'per read', () async {
      final site = LaneSite(
        (_, read) => read == 0 ? unreadable : laneBody(newBytes),
      );
      await harness(written(), site).check.run(requestFor(written()));

      expect(site.reads.map((r) => r.$1), everyElement('availability.json'));
      expect(
        site.reads.map((r) => r.$2),
        everyElement(AvailabilityDocument.readerMaxBytes),
      );
      expect(site.reads.map((r) => r.$3), ['7-0', '7-1']);
    });

    test('a 404 for a file proof means "still building" (first publish), '
        'not a contradiction', () async {
      final site = LaneSite(
        (_, read) => read < 2 ? absent : laneBody(newBytes),
      );
      final h = harness(written(), site);

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.live,
      );
    });

    test('a removal is proven by an exact 404', () async {
      final site = LaneSite(
        (_, read) => read < 2 ? laneBody(oldBytes) : absent,
      );
      final h = harness(removed(), site);

      expect(
        await h.check.run(requestFor(removed())),
        DeferredVerificationOutcome.live,
      );
      expect(h.manifest.current.state, PublishState.live);
    });

    test('out of budget: notProven, the record stays deployed, nothing is '
        'recorded — never "contradicted"', () async {
      final site = LaneSite((_, _) => laneBody(oldBytes));
      final h = harness(written(), site);

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.notProven,
      );
      expect(site.reads, hasLength(ReadBackBudget.deferredAttempts));
      expect(h.manifest.saves, isEmpty);
      expect(h.manifest.current.state, PublishState.deployed);
      expect(h.recorder.recorded, isEmpty);
    });

    test('a removal whose file is still served keeps waiting', () async {
      final site = LaneSite((_, _) => laneBody(oldBytes));
      final h = harness(removed(), site);

      expect(
        await h.check.run(requestFor(removed())),
        DeferredVerificationOutcome.notProven,
      );
      expect(h.manifest.saves, isEmpty);
    });

    test('an adapter that throws counts as "not yet"', () async {
      final site = LaneSite()..throws = true;
      final h = harness(written(), site);

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.notProven,
      );
      expect(site.reads, hasLength(ReadBackBudget.deferredAttempts));
    });
  });

  group('only an unchanged deployed record is upgraded', () {
    test(
      'another commit before the proof: superseded, reading stops',
      () async {
        final site = LaneSite((_, _) => laneBody(oldBytes));
        late final ({
          DeferredPublishVerification check,
          LaneMemManifest manifest,
          LaneRecorder recorder,
          List<Duration> sleeps,
        })
        h;
        h = harness(
          written(),
          site,
          // During the second wait, another publish commits.
          onSleep: (sleep) {
            if (sleep == 2) h.manifest.current = written(head: 'commit-2');
          },
        );

        expect(
          await h.check.run(requestFor(written())),
          DeferredVerificationOutcome.superseded,
        );
        expect(site.reads, hasLength(1));
        expect(h.manifest.saves, isEmpty);
      },
    );

    test('a record that is already live is not touched again', () async {
      final h = harness(written().asLive(), LaneSite((_, _) => absent));
      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.superseded,
      );
      expect(h.manifest.saves, isEmpty);
      expect(h.recorder.recorded, isEmpty);
    });

    test('the upgrade waits for the publish queue, and re-checks the record '
        'inside it', () async {
      final queue = SerialOpQueue();
      final release = Completer<void>();
      final h = harness(
        written(),
        LaneSite((_, _) => laneBody(newBytes)),
        queue: queue,
      );
      // A publish holds the queue and commits again before releasing it.
      final publish = queue.enqueue(() async {
        await release.future;
        h.manifest.current = written(head: 'commit-2');
      });

      final outcome = h.check.run(requestFor(written()));
      await Future<void>.delayed(Duration.zero);
      expect(h.manifest.saves, isEmpty, reason: 'still queued');
      release.complete();
      await publish;

      expect(await outcome, DeferredVerificationOutcome.superseded);
      expect(h.manifest.current.headSha, 'commit-2');
      expect(h.manifest.current.state, PublishState.deployed);
      expect(h.recorder.recorded, isEmpty);
    });

    test(
      'a failed live save is reported and does not advance the journal',
      () async {
        final h = harness(written(), LaneSite((_, _) => laneBody(newBytes)));
        h.manifest.liveSaveFails = true;

        expect(
          await h.check.run(requestFor(written())),
          DeferredVerificationOutcome.notSaved,
        );
        expect(h.manifest.current.state, PublishState.deployed);
        expect(h.recorder.recorded, isEmpty);
      },
    );

    test('a failed journal write after the live save is reported', () async {
      final h = harness(written(), LaneSite((_, _) => laneBody(newBytes)));
      h.recorder.fails = true;

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.notSaved,
      );
      expect(h.manifest.current.state, PublishState.live);
    });
  });

  group('cancel (owner disposed)', () {
    test('during a wait: no more reads, nothing written', () async {
      final site = LaneSite((_, _) => laneBody(newBytes));
      late final ({
        DeferredPublishVerification check,
        LaneMemManifest manifest,
        LaneRecorder recorder,
        List<Duration> sleeps,
      })
      h;
      h = harness(written(), site, onSleep: (_) => h.check.cancel());

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.cancelled,
      );
      expect(h.check.isCancelled, isTrue);
      expect(site.reads, isEmpty);
      expect(h.manifest.saves, isEmpty);
    });

    test('while the upgrade waits in the queue: nothing written', () async {
      final queue = SerialOpQueue();
      final release = Completer<void>();
      final h = harness(
        written(),
        LaneSite((_, _) => laneBody(newBytes)),
        queue: queue,
      );
      final held = queue.enqueue(() => release.future);

      final outcome = h.check.run(requestFor(written()));
      await Future<void>.delayed(Duration.zero);
      h.check.cancel();
      release.complete();
      await held;

      expect(await outcome, DeferredVerificationOutcome.cancelled);
      expect(h.manifest.saves, isEmpty);
      expect(h.recorder.recorded, isEmpty);
    });

    test('a cancelled instance ends any later run at once', () async {
      final site = LaneSite((_, _) => laneBody(newBytes));
      final h = harness(written(), site)..check.cancel();

      expect(
        await h.check.run(requestFor(written())),
        DeferredVerificationOutcome.cancelled,
      );
      expect(site.reads, isEmpty);
    });
  });
}
