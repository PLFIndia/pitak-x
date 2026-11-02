import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';

import '../support/availability_lane_fakes.dart';

/// The availability lane (ADR 0019 Decisions 6–9, plan C.4; the "Lane" row
/// of plan C.11). Time runs under `fake_async`; storage, keys and the network
/// are fakes, so nothing real is touched.
void main() {
  final gitHub = GitHubPublishTarget.create('me/lib')!;
  final otherRepo = GitHubPublishTarget.create('me/other')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;

  const oneCopy = CatalogueItem(id: 1, title: 'One copy');
  const threeCopies = CatalogueItem(id: 2, title: 'Three', copyCount: 3);
  const another = CatalogueItem(id: 3, title: 'Another');
  const items = [oneCopy, threeCopies, another];

  String keyOf(int id) => id.toRadixString(16).padLeft(16, '0');

  AvailabilityLaneInputs on({Map<int, int>? counts, List<CatalogueItem>? of}) =>
      AvailabilityLaneInputs(
        enabled: true,
        activeCounts: counts,
        items: of ?? items,
      );

  const off = AvailabilityLaneInputs(enabled: false);

  group('changes and pacing (AV5–AV7)', () {
    test('unknown counts never publish, and say why', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on());
        fake.elapse(const Duration(hours: 1));

        expect(h.sent, isEmpty);
        expect(
          (h.status as AvailabilityLaneNotReady).reason,
          AvailabilityLaneMessages.unlockVault,
        );
        expect(
          h.store.saved,
          isNull,
          reason: 'nothing computed, nothing saved',
        );
      });
    });

    test('a loan is saved FIRST, then published 20 s after the change', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {}));
        expect(h.store.saved!.pending!.keys, isEmpty, reason: 'computed');
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(1), reason: 'the first set goes out too');
        h.sent.clear();

        h.update(on(counts: {1: 1}));
        expect(h.store.saved!.pending!.keys, [keyOf(1)]);
        expect(h.status, isA<AvailabilityLaneScheduled>());
        fake.elapse(const Duration(seconds: 19));
        expect(h.sent, isEmpty);
        fake.elapse(const Duration(seconds: 1));

        final write = h.sent.single as AvailabilityWrite;
        expect(write.snapshot.keys, [keyOf(1)]);
        expect(h.status, isA<AvailabilityLaneUpToDate>());
        expect(h.store.saved!.pending, isNull);
        expect(h.store.saved!.published!.describes(cloudflare), isTrue);
      });
    });

    test('lending the second copy of a three-copy book publishes nothing', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {}));
        fake.elapse(const Duration(seconds: 30));
        h.sent.clear();

        h
          ..update(on(counts: {2: 1}))
          ..update(on(counts: {2: 2}));
        fake.elapse(const Duration(minutes: 10));

        expect(h.sent, isEmpty);
        expect(h.status, isA<AvailabilityLaneUpToDate>());
      });
    });

    test('five loans at the counter become ONE publish (debounce)', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {}));
        fake.elapse(const Duration(seconds: 30));
        h.sent.clear();

        h.update(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 10));
        h.update(on(counts: {1: 1, 3: 1}));
        fake.elapse(const Duration(seconds: 10));
        h.update(on(counts: {3: 1}));
        fake.elapse(const Duration(seconds: 19));
        expect(h.sent, isEmpty);
        fake.elapse(const Duration(seconds: 1));

        expect((h.sent.single as AvailabilityWrite).snapshot.keys, [keyOf(3)]);
      });
    });

    test('the vault locks before the timer: the saved set still goes out', () {
      fakeAsync((fake) {
        // The second input: counts unknown again (the vault locked).
        final h = _Lane(fake, gitHub)
          ..start(on(counts: {1: 1}))
          ..update(on());
        fake.elapse(const Duration(seconds: 20));

        expect((h.sent.single as AvailabilityWrite).snapshot.keys, [keyOf(1)]);
      });
    });

    test(
      'a set saved before a restart is published at start, counts or not',
      () {
        fakeAsync((fake) {
          final saved = AvailabilitySnapshot.tryCreate(
            keys: [keyOf(1)],
            asOfMillis: 60000,
          )!;
          final h = _Lane(
            fake,
            gitHub,
            initial: AvailabilityLaneState(pending: saved),
          )..start(on());
          fake.flushMicrotasks();

          expect((h.sent.single as AvailabilityWrite).snapshot.asOf, 60000);
        });
      },
    );

    test('the same set already on the SAME site is not sent; a moved site '
        'gets it', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h.sent.clear();

        h.update(on(counts: {1: 1}, of: [...items]));
        fake.elapse(const Duration(minutes: 30));
        expect(h.sent, isEmpty);

        h
          ..target = Right(otherRepo)
          ..update(on(counts: {1: 1}, of: [...items]));
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(1));
        expect(h.sentTo.last, same(otherRepo));
      });
    });

    test('unreadable keys stop the lane and say so (nothing sent)', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..keysFail = true
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(minutes: 5));

        expect(h.sent, isEmpty);
        expect(
          (h.status as AvailabilityLaneNotReady).reason,
          PublishItemKeys.saltUnavailableMessage,
        );
      });
    });
  });

  group('GitHub pacing (AV6)', () {
    test('a second availability publish waits 6 min after the first', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(1));

        h.update(on(counts: {1: 1, 3: 1}));
        fake.elapse(const Duration(minutes: 5));
        expect(h.sent, hasLength(1));
        fake.elapse(const Duration(seconds: 41));
        expect(h.sent, hasLength(2));
      });
    });

    test('Cloudflare has no spacing: the debounce only', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h.update(on(counts: {1: 1, 3: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(2));
      });
    });

    test('a used-up hourly budget delays the automatic publish; the button '
        'goes now and says GitHub may delay it', () {
      fakeAsync((fake) {
        const now = _Lane.base;
        final h = _Lane(
          fake,
          gitHub,
          initial: AvailabilityLaneState(
            gitHubCommitTimes: [for (var i = 0; i < 10; i++) now - i * 1000],
          ),
        )..start(on(counts: {1: 1}));
        fake.elapse(const Duration(minutes: 30));
        expect(h.sent, isEmpty, reason: 'the budget frees up after 60 min');

        h.publishNow();
        expect(
          h.views
              .map((view) => view.status)
              .whereType<AvailabilityLaneScheduled>()
              .last
              .gitHubMayDelay,
          isTrue,
        );
        expect(h.sent, hasLength(1), reason: 'the tap goes at once');
      });
    });
  });

  group('outcomes (status mapping)', () {
    test('live → up to date with the set time', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        final status = h.status as AvailabilityLaneUpToDate;
        expect(status.asOf, AvailabilitySnapshot.floorToMinute(_Lane.base));
      });
    });

    test('going live → going live, then up to date once proven', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..answer = ((update, target) => AvailabilityGoingLive(
            acceptedAt: _Lane.base,
            verification: _request(gitHub),
          ))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.status, isA<AvailabilityLaneGoingLive>());
        expect(h.proofs, hasLength(1));

        h.proveResult = DeferredVerificationOutcome.live;
        fake.elapse(const Duration(seconds: 1));
        expect(h.status, isA<AvailabilityLaneUpToDate>());
        expect(
          h.store.saved!.published!.publishedAt,
          _Lane.base,
          reason: 'the commit is the GitHub spacing anchor',
        );
      });
    });

    test('already published → up to date, nothing pending', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..answer = ((_, _) => const AvailabilityAlreadyPublished())
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.status, isA<AvailabilityLaneUpToDate>());
        expect(h.store.saved!.pending, isNull);
        expect(h.store.saved!.published!.publishedAt, 0);
      });
    });

    test('not ready waits: no timer retries it; a catalogue publish does', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..answer = ((_, _) => const AvailabilityNotReady(
            AvailabilityPublishMessages.catalogueNotKeyed,
          ))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(
          (h.status as AvailabilityLaneNotReady).reason,
          AvailabilityPublishMessages.catalogueNotKeyed,
        );
        h.resumed();
        fake.elapse(const Duration(hours: 2));
        expect(h.sent, hasLength(1), reason: 'neither timer nor resume');
        expect(h.store.saved!.pending, isNotNull, reason: 'the set is kept');

        h
          ..answer = _Lane.live
          ..sitePublished();
        fake.elapse(const Duration(seconds: 1));
        expect(h.sent, hasLength(2));
        expect(h.status, isA<AvailabilityLaneUpToDate>());
      });
    });

    test('pending retries on the backoff (1, 2, 5, 10 min), never a loop', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..answer = ((_, _) => const AvailabilityPending('No connection.'))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(1));
        final pending = h.status as AvailabilityLanePending;
        expect(pending.reason, 'No connection.');
        expect(pending.retryAt, isNotNull);

        for (final (minutes, total) in [
          (1, 2),
          (2, 3),
          (5, 4),
          (10, 5),
          (10, 6),
        ]) {
          fake.elapse(Duration(minutes: minutes) - const Duration(seconds: 1));
          expect(h.sent, hasLength(total - 1));
          fake.elapse(const Duration(seconds: 1));
          expect(h.sent, hasLength(total));
        }
      });
    });

    test('a site only the user can repair retries at the slowest pace', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..answer = ((_, _) =>
              const AvailabilityPending(AvailabilityPublishMessages.repairSite))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h.resumed(); // a resume does not hurry a repair
        fake.elapse(const Duration(minutes: 9, seconds: 59));
        expect(h.sent, hasLength(1));
        fake.elapse(const Duration(seconds: 1));
        expect(h.sent, hasLength(2));
      });
    });

    test('a resume retries a failed publish at once (G.4 row 6)', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..answer = ((_, _) => const AvailabilityPending('No connection.'))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..answer = _Lane.live
          ..resumed();
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(2));
        expect(h.status, isA<AvailabilityLaneUpToDate>());
      });
    });

    test('blocked (no host, a pending move) waits and says why', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..blockWith = 'Connect a publishing host first.'
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(
          (h.status as AvailabilityLaneNotReady).reason,
          'Connect a publishing host first.',
        );
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 1);
      });
    });

    test('no target even for pacing: nothing is scheduled', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..target = const Left('Connect a publishing host first.')
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 0);
        expect(h.status, isA<AvailabilityLaneNotReady>());
      });
    });
  });

  group('a stale file after "not ready" (plan S6)', () {
    test('a removed stale file forgets the published record', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.store.saved!.published, isNotNull);

        h
          ..answer = _Lane.staleNotReady
          ..removal = AvailabilityGoingLive(
            acceptedAt: _Lane.base,
            verification: _request(gitHub, absent: true),
          )
          ..update(on(counts: {3: 1}));
        fake.elapse(const Duration(minutes: 7));

        expect(h.status, isA<AvailabilityLaneNotReady>());
        expect(h.store.saved!.published, isNull);
        expect(h.store.saved!.pending, isNotNull);
        expect(h.proofs, hasLength(1), reason: 'the removal is proven too');
      });
    });

    test('a failed removal retries on the backoff', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..answer = _Lane.staleNotReady
          ..removal = const AvailabilityPending('No connection.')
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.status, isA<AvailabilityLanePending>());
        fake.elapse(const Duration(minutes: 1));
        expect(h.runs, 2);
      });
    });
  });

  group('the switch (AV4)', () {
    test('off publishes exactly ONE removal, then clears the saved sets', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..sent.clear()
          ..update(off);
        fake.elapse(const Duration(minutes: 7));

        expect(h.sent.single, isA<AvailabilityDelete>());
        expect(h.status, isA<AvailabilityLaneOff>());
        expect(h.store.saved!.holdsNoSnapshots, isTrue);

        h.update(
          const AvailabilityLaneInputs(enabled: false, activeCounts: {}),
        );
        fake.elapse(const Duration(hours: 1));
        expect(h.sent, hasLength(1), reason: 'loans no longer publish');
      });
    });

    test('off with nothing saved sends nothing', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(off);
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 0);
        expect(h.status, isA<AvailabilityLaneOff>());
      });
    });

    test('off with an unreadable store still checks for a file to remove', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub, raw: '{"version":1}')..start(off);
        fake.elapse(const Duration(seconds: 1));
        expect(h.sent.single, isA<AvailabilityDelete>());
      });
    });

    test('back on publishes the CURRENT set, never an old one', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h.update(off);
        fake.elapse(const Duration(seconds: 1));
        h
          ..sent.clear()
          ..update(on(counts: {3: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect((h.sent.single as AvailabilityWrite).snapshot.keys, [keyOf(3)]);
      });
    });

    test('settings not known yet: nothing at all happens', () {
      fakeAsync((fake) {
        final h = _Lane(
          fake,
          gitHub,
        )..start(const AvailabilityLaneInputs(enabled: null, activeCounts: {}));
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 0);
        expect(h.status, isA<AvailabilityLaneStarting>());
      });
    });
  });

  group('a damaged store never yields an empty list', () {
    test('locked vault + damaged store: nothing is published', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub, raw: '{"version":1,"pending":{}}')
          ..start(on());
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 0);
      });
    });

    test('known counts compute a fresh set over the damage', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub, raw: 'garbage')
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect((h.sent.single as AvailabilityWrite).snapshot.keys, [keyOf(1)]);
      });
    });
  });

  group('plan J9: the library was replaced', () {
    test('every saved set is forgotten; only fresh counts publish again', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..answer = ((_, _) => const AvailabilityPending('No connection.'))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.store.saved!.pending, isNotNull);

        h
          ..answer = _Lane.live
          ..libraryReplaced(on());
        fake.elapse(const Duration(hours: 1));

        expect(h.runs, 1, reason: 'the old set never goes out');
        expect(h.store.saved!.holdsNoSnapshots, isTrue);
      });
    });
  });

  group('the one-time notice', () {
    test('is due once the lane is active, and stays dismissed', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.views.last.noticeDue, isTrue);

        h.dismissNotice();
        expect(h.views.last.noticeDue, isFalse);
        expect(h.store.saved!.noticeShown, isTrue);
      });
    });

    test('is not due while the lane is off or not ready', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on());
        expect(h.views.last.noticeDue, isFalse);
      });
    });
  });

  group('edges (plan S6)', () {
    test('a change DURING a publish is sent right after it', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..gate = Completer<void>()
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.status, isA<AvailabilityLanePublishing>());

        h.update(on(counts: {1: 1, 3: 1}));
        h.gate!.complete();
        h.gate = null;
        fake.elapse(Duration.zero);
        expect(h.runs, 1);
        expect(h.store.saved!.pending!.keys, hasLength(2), reason: 'kept');
        fake.elapse(const Duration(seconds: 20));

        expect(h.runs, 2);
        expect((h.sent.last as AvailabilityWrite).snapshot.keys, hasLength(2));
      });
    });

    test('switched back on while the removal ran: a new set is kept', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..gate = Completer<void>()
          ..update(off);
        expect(h.status, isA<AvailabilityLanePublishing>());

        h.update(on(counts: {3: 1}));
        h.gate!.complete();
        h.gate = null;
        fake.elapse(const Duration(seconds: 21));

        expect(h.sent[1], isA<AvailabilityDelete>());
        expect((h.sent.last as AvailabilityWrite).snapshot.keys, [keyOf(3)]);
      });
    });

    test('the button with the switch off sends a due removal at once', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..update(off) // GitHub spacing would delay the removal 6 min...
          ..publishNow(); // ...the tap does not wait.
        expect(h.sent.last, isA<AvailabilityDelete>());
        expect(h.status, isA<AvailabilityLaneOff>());
      });
    });

    test('a key that is not publishable stops the set (fail closed)', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..keysOverride = {1: 'NOT-A-KEY'}
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(hours: 1));
        expect(h.runs, 0);
        expect(h.status, isA<AvailabilityLaneNotReady>());
      });
    });

    test('an unreadable catalogue with known counts says so', () {
      fakeAsync((fake) {
        final h = _Lane(
          fake,
          gitHub,
        )..start(const AvailabilityLaneInputs(enabled: true, activeCounts: {}));
        expect(h.status, isA<AvailabilityLaneNotReady>());
        expect(h.runs, 0);
      });
    });

    test('the same set with no host now: not ready, nothing sent', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..target = const Left('Connect a publishing host first.')
          ..update(on(counts: {1: 1}, of: [...items]));
        expect(h.status, isA<AvailabilityLaneNotReady>());
        expect(h.runs, 1);
      });
    });

    test('a running deferred check keeps "going live" for the same set', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)
          ..answer = ((update, target) => AvailabilityGoingLive(
            acceptedAt: _Lane.base,
            verification: _request(gitHub),
          ))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h.update(on(counts: {1: 1}, of: [...items]));
        expect(h.status, isA<AvailabilityLaneGoingLive>());
      });
    });

    test('"already published" keeps the earlier GitHub spacing anchor', () {
      fakeAsync((fake) {
        final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..answer = ((_, _) => const AvailabilityAlreadyPublished())
          ..update(on(counts: {3: 1}));
        fake.elapse(const Duration(minutes: 7));
        expect(h.store.saved!.published!.publishedAt, _Lane.base);
      });
    });

    test('a stale file already gone is simply forgotten', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..answer = _Lane.staleNotReady
          ..removal = const AvailabilityAlreadyPublished()
          ..update(on(counts: {3: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.store.saved!.published, isNull);
        expect(h.status, isA<AvailabilityLaneNotReady>());
      });
    });

    test('a store that cannot save still publishes from memory', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare);
        h.store.failWrites = true;
        h.start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        expect(h.sent, hasLength(1));
        expect(h.store.saved, isNull);
      });
    });

    test('a restore while the switch is off keeps the due removal', () {
      fakeAsync((fake) {
        final h = _Lane(fake, cloudflare)
          ..answer = ((_, _) => const AvailabilityPending('No connection.'))
          ..start(on(counts: {1: 1}));
        fake.elapse(const Duration(seconds: 20));
        h
          ..answer = _Lane.live
          ..libraryReplaced(off);
        expect(h.sent.last, isA<AvailabilityDelete>());
      });
    });
  });

  test('dispose stops every timer', () {
    fakeAsync((fake) {
      final h = _Lane(fake, gitHub)..start(on(counts: {1: 1}));
      h.lane.dispose();
      fake.elapse(const Duration(hours: 1));
      expect(h.runs, 0);
    });
  });

  test('update availability now publishes at once, skipping the debounce', () {
    fakeAsync((fake) {
      final h = _Lane(fake, gitHub)
        ..start(on(counts: {1: 1}))
        ..publishNow();
      expect(h.sent, hasLength(1));
      expect(h.status, isA<AvailabilityLaneUpToDate>());
    });
  });
}

DeferredVerificationRequest _request(
  GitHubPublishTarget target, {
  bool absent = false,
}) => DeferredVerificationRequest.forRecord(
  target: target,
  record: PublishManifest(
    repo: target.ownerRepo,
    branch: 'main',
    headSha: 'c1',
    fileShas: absent
        ? const {'books.json': 'b1'}
        : const {'books.json': 'b1', 'availability.json': 'a1'},
    proofPath: absent
        ? PublishProofPath.availabilityJsonAbsent
        : PublishProofPath.availabilityJson,
  ),
  revision: 1,
)!;

/// One lane over fakes, driven synchronously under `fake_async`.
final class _Lane {
  _Lane(
    this.fake,
    PublishTarget initialTarget, {
    AvailabilityLaneState? initial,
    String? raw,
  }) : target = Right(initialTarget),
       store = raw == null
           ? MemoryAvailabilityLaneStore(initial)
           : MemoryAvailabilityLaneStore.raw(raw) {
    lane = AvailabilityLane(
      repository: AvailabilityLaneRepository(store),
      keysFor: (ids) async => keysFail
          ? const Left(
              ValidationFailure(PublishItemKeys.saltUnavailableMessage),
            )
          : keysOverride != null
          ? Right(keysOverride!)
          : Right({
              for (final id in ids) id: id.toRadixString(16).padLeft(16, '0'),
            }),
      publish: _publish,
      currentTarget: () async => target,
      prove: (request) async {
        proofs.add(request);
        while (proveResult == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        return proveResult!;
      },
      onView: views.add,
      clock: () => base + fake.elapsed.inMilliseconds,
    );
  }

  /// The fake wall clock at the start of every test (epoch milliseconds).
  static const int base = 1761984000000;

  static AvailabilityPublishResult live(
    AvailabilityUpdate update,
    PublishTarget target,
  ) => const AvailabilityLive(acceptedAt: base);

  /// Gate 7b failed while the record still shows a file (plan S6).
  static AvailabilityPublishResult staleNotReady(
    AvailabilityUpdate update,
    PublishTarget target,
  ) => const AvailabilityNotReady(
    AvailabilityPublishMessages.catalogueNotKeyed,
    staleFileRecorded: true,
  );

  final FakeAsync fake;
  final MemoryAvailabilityLaneStore store;
  late final AvailabilityLane lane;

  Either<String, PublishTarget> target;
  AvailabilityPublishResult Function(AvailabilityUpdate, PublishTarget) answer =
      live;
  AvailabilityPublishResult? removal;
  String? blockWith;
  bool keysFail = false;
  DeferredVerificationOutcome? proveResult;

  /// While set, a publish waits for it (to act DURING a publish).
  Completer<void>? gate;

  /// Keys the fake returns instead of the derived ones (to force a bad key).
  Map<int, String>? keysOverride;

  final List<AvailabilityUpdate> sent = [];
  final List<PublishTarget> sentTo = [];
  final List<DeferredVerificationRequest> proofs = [];
  final List<AvailabilityLaneView> views = [];
  int runs = 0;

  AvailabilityLaneStatus get status => lane.status;

  Future<AvailabilityRun> _publish(AvailabilityUpdate update) async {
    runs++;
    final hold = gate;
    if (hold != null) await hold.future;
    final blocked = blockWith;
    if (blocked != null) return AvailabilityRunBlocked(blocked);
    final to = target.toNullable()!;
    sent.add(update);
    sentTo.add(to);
    final result = answer(update, to);
    final stale = result is AvailabilityNotReady && result.staleFileRecorded;
    return AvailabilityRunFinished(
      target: to,
      result: result,
      removal: stale ? removal : null,
    );
  }

  void start(AvailabilityLaneInputs inputs) => _step(lane.start(inputs));
  void update(AvailabilityLaneInputs inputs) => _step(lane.update(inputs));
  void resumed() => _step(lane.resumed());
  void sitePublished() => _step(lane.sitePublished());
  void publishNow() => _step(lane.publishNow());
  void dismissNotice() => _step(lane.dismissNotice());
  void libraryReplaced(AvailabilityLaneInputs inputs) =>
      _step(lane.libraryReplaced(inputs));

  /// Runs [step] and everything due "now" (microtasks and zero timers).
  void _step(Future<void> step) {
    step.ignore();
    fake.elapse(Duration.zero);
  }
}
