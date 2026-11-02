import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_going_live_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

import '../support/cloudflare_fakes.dart';
import '../support/github_lane_fakes.dart';

/// Plan SP1: a GitHub catalogue or events publish returns at commit time and
/// `PublishGoingLive` proves the commit afterwards, outside the publish queue
/// (ADR 0017 amendment of 2026-11-02). `ProviderContainer` overrides only; no
/// real network, storage or wall-clock waiting (`fake_async`).
void main() {
  final target = GitHubPublishTarget.create('me/lib')!;
  final books = utf8.encode('{"books":[1]}');

  /// The record a GitHub catalogue commit leaves: `deployed`, with its proof.
  PublishManifest deployed({String head = 'NEWCOMMIT'}) => PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: head,
    ownershipConfirmed: true,
    fileShas: {'books.json': laneSha(books), 'index.html': 'i1'},
    proofPath: PublishProofPath.booksJson,
    committedAt: 1000,
  );

  late LaneMemManifest manifest;
  late LaneSite site;
  late FakePublishHostStateStore journal;
  late int statusBuilds;
  late int manifestOpens;
  late bool manifestOpenFails;

  setUp(() {
    manifest = LaneMemManifest(deployed());
    site = LaneSite();
    journal = FakePublishHostStateStore(
      const PublishHostState(activeHost: PublishHost.github),
    );
    statusBuilds = 0;
    manifestOpens = 0;
    manifestOpenFails = false;
  });

  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [
        publishedSiteReadVerifierProvider.overrideWithValue(site),
        publishManifestStoreProvider.overrideWith((ref) async {
          manifestOpens++;
          if (manifestOpenFails) throw StateError('docs dir unavailable');
          return manifest;
        }),
        publishHostStateRepositoryProvider.overrideWith(
          (ref) async => PublishHostStateRepository(
            store: journal,
            manifest: manifest,
            verifier: FakePublishedSiteVerifier(),
          ),
        ),
        // Counts rebuilds: a proven commit must refresh the card's status.
        publishSiteStatusProvider.overrideWith((ref) async {
          statusBuilds++;
          return const PublishSiteStatus(
            activeHost: PublishHost.github,
            target: null,
            verifiedSiteUrl: null,
            setupMessage: null,
          );
        }),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  DeferredVerificationRequest requestFor(PublishManifest record) =>
      DeferredVerificationRequest.forRecord(
        target: target,
        record: record,
        revision: 1000,
      )!;

  test('a commit GitHub serves is proven: the record turns live, the address '
      'is recorded and the share address and the card status are read '
      'afresh', () {
    fakeAsync((fake) {
      final c = container();
      final shared = <String?>[];
      c
        ..listen(
          publishedSiteUrlProvider,
          (_, next) => shared.add(next.valueOrNull),
          fireImmediately: true,
        )
        ..listen(publishSiteStatusProvider, (_, _) {});
      fake.flushMicrotasks();
      final buildsBefore = statusBuilds;
      // Pages still serves the old file at the first read, the new one next.
      site.answer = (_, read) =>
          read == 0 ? laneBody(utf8.encode('old')) : laneBody(books);

      final request = requestFor(manifest.current);
      DeferredVerificationOutcome? outcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(request)
          .then((value) => outcome = value);
      // Registered at once: the card already says "going live".
      final running = c.read(publishGoingLiveProvider).checkOf(request);
      expect(running, isNotNull);
      expect(running!.outcome, isNull);

      fake.elapse(ReadBackBudget.deferredFirstDelay);
      expect(outcome, isNull, reason: 'old bytes mean "still building"');
      fake.elapse(ReadBackBudget.deferredInterval);

      expect(outcome, DeferredVerificationOutcome.live);
      expect(
        c.read(publishGoingLiveProvider).checkOf(request)!.outcome,
        DeferredVerificationOutcome.live,
      );
      expect(manifest.current.state, PublishState.live);
      expect(journal.stored!.verifiedSiteUrl, target.siteUrl);
      expect(site.reads.map((read) => read.$1), ['books.json', 'books.json']);
      expect(shared.last, target.siteUrl);
      expect(statusBuilds, greaterThan(buildsBefore));
    });
  });

  test('out of budget: not proven, the record stays deployed and no address '
      'is recorded', () {
    fakeAsync((fake) {
      final c = container();
      site.answer = (_, _) => laneBody(utf8.encode('old'));
      final request = requestFor(manifest.current);
      DeferredVerificationOutcome? outcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(request)
          .then((value) => outcome = value);

      fake.elapse(ReadBackBudget.deferredTotal + const Duration(seconds: 1));

      expect(outcome, DeferredVerificationOutcome.notProven);
      expect(site.reads, hasLength(ReadBackBudget.deferredAttempts));
      expect(manifest.current.state, PublishState.deployed);
      expect(journal.stored!.verifiedTarget, isNull);
    });
  });

  test('a newer commit supersedes the check before it reads', () {
    fakeAsync((fake) {
      final c = container();
      final request = requestFor(manifest.current);
      DeferredVerificationOutcome? outcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(request)
          .then((value) => outcome = value);
      fake.flushMicrotasks();
      // Another publish (events, the lane, a second catalogue) committed.
      manifest.current = deployed(head: 'NEWER');

      fake.elapse(ReadBackBudget.deferredFirstDelay);

      expect(outcome, DeferredVerificationOutcome.superseded);
      expect(site.reads, isEmpty);
      expect(manifest.saves, isEmpty);
    });
  });

  test('disposing the owner cancels a running check: nothing more is read '
      'or written', () {
    fakeAsync((fake) {
      final c = ProviderContainer(
        overrides: [
          publishedSiteReadVerifierProvider.overrideWithValue(site),
          publishManifestStoreProvider.overrideWith((ref) async => manifest),
        ],
      );
      site.answer = (_, _) => laneBody(books);
      final request = requestFor(manifest.current);
      DeferredVerificationOutcome? outcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(request)
          .then((value) => outcome = value);
      fake.flushMicrotasks();

      c.dispose();
      fake.elapse(ReadBackBudget.deferredTotal);

      expect(outcome, DeferredVerificationOutcome.cancelled);
      expect(site.reads, isEmpty);
      expect(manifest.saves, isEmpty);
    });
  });

  test('a check that cannot start fails closed as "not proven", and the next '
      'publish tries again', () {
    fakeAsync((fake) {
      final c = container();
      manifestOpenFails = true;
      final first = requestFor(manifest.current);
      DeferredVerificationOutcome? firstOutcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(first)
          .then((value) => firstOutcome = value);
      fake.flushMicrotasks();
      expect(firstOutcome, DeferredVerificationOutcome.notProven);
      expect(manifest.current.state, PublishState.deployed);

      // The provider the failed open used is disposed, so it opens again.
      fake.elapse(Duration.zero);
      manifestOpenFails = false;
      site.answer = (_, _) => laneBody(books);
      final second = requestFor(manifest.current);
      DeferredVerificationOutcome? secondOutcome;
      c
          .read(publishGoingLiveProvider.notifier)
          .track(second)
          .then((value) => secondOutcome = value);
      fake.elapse(ReadBackBudget.deferredFirstDelay);

      expect(manifestOpens, 2);
      expect(secondOutcome, DeferredVerificationOutcome.live);
    });
  });

  test('proveLater starts a check only for a result that carries one', () {
    fakeAsync((fake) {
      final c = container();
      final notifier = c.read(publishGoingLiveProvider.notifier);
      final request = requestFor(manifest.current);

      notifier
        ..proveLater(const PublishFailure('nope'))
        ..proveLater(
          const PublishSuccess(
            pagesUrl: 'https://me.github.io/lib/',
            uploadedPaths: [],
          ),
        );
      expect(c.read(publishGoingLiveProvider).checkOf(request), isNull);
      expect(manifestOpens, 0);

      notifier.proveLater(
        PublishSuccess(
          pagesUrl: target.siteUrl,
          uploadedPaths: const [],
          verification: request,
        ),
      );
      expect(c.read(publishGoingLiveProvider).checkOf(request), isNotNull);
      fake.elapse(ReadBackBudget.deferredTotal);
    });
  });

  group('PublishGoingLiveState', () {
    test('finds a check by the very request, not by an equal one', () {
      final request = requestFor(deployed());
      final twin = requestFor(deployed());
      final state = PublishGoingLiveState.empty.withCheck(
        PublishGoingLiveCheck(request),
      );
      expect(state.checkOf(request), isNotNull);
      expect(state.checkOf(twin), isNull);
    });

    test('an ended check replaces its running one; at most '
        'maxRemembered checks are kept, the oldest forgotten first', () {
      final requests = [
        for (var i = 0; i <= PublishGoingLiveState.maxRemembered; i++)
          requestFor(deployed(head: 'H$i')),
      ];
      var state = PublishGoingLiveState.empty;
      for (final request in requests) {
        state = state.withCheck(PublishGoingLiveCheck(request));
      }
      expect(state.checkOf(requests.first), isNull);
      expect(state.checkOf(requests.last)!.outcome, isNull);

      state = state.withCheck(
        PublishGoingLiveCheck(
          requests.last,
          DeferredVerificationOutcome.notProven,
        ),
      );
      expect(
        state.checkOf(requests.last)!.outcome,
        DeferredVerificationOutcome.notProven,
      );
      expect(state.checkOf(requests[1]), isNotNull);
    });
  });
}
