import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/application/publish_events_controller.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_going_live_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import 'support/cloudflare_fakes.dart';
import 'support/going_live_fakes.dart';

const _safeReadFailure =
    'Could not read the library. Nothing was published. '
    'Please try again.';

void main() {
  testWidgets('M10: failed catalogue read must not publish an empty library', (
    tester,
  ) async {
    final h = _Harness();
    h.books.read = () async => left(const StorageFailure('private-db-detail'));
    final result = await h.publish(tester);

    expect(result, isA<PublishFailure>());
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  for (final failure in const <Failure>[
    StorageFailure('private-db-detail'),
    UnexpectedFailure('private-debug-detail'),
    ValidationFailure('private-validation-detail'),
    NotFoundFailure(),
    NetworkFailure(),
    CryptoFailure('private-crypto-detail'),
    WrongPassphraseFailure(),
    BackupCorruptFailure('private-archive-detail'),
    SchemaTooNewFailure(99),
  ]) {
    testWidgets('${failure.runtimeType} stops preparation with a safe result', (
      tester,
    ) async {
      final h = _Harness();
      final before = h.manifest.current;
      h.books.read = () async => left(failure);
      final result = await h.publish(tester);

      expect((result as PublishFailure).reason, _safeReadFailure);
      expect(h.states.last.requireValue, same(result));
      expect(h.states.any((state) => state.isLoading), isTrue);
      expect(h.states.any((state) => state.hasError), isFalse);
      expect(h.books.reads, 1);
      // ONE local read resolves the operation's sealed target (R1/C3) before
      // the strict reads. That is a repo-name lookup, not a token read: the
      // token is only fetched once the library itself has been read.
      expect(h.credentials.reads, 1);
      expect(h.api.reads, 0);
      expect(h.api.commits, isEmpty);
      expect(h.manifest.loads, 0);
      expect(h.manifest.saves, 0);
      expect(h.manifest.current, same(before));
      expect(h.viewerBuilds, 0);
      expect(h.remoteReads, 0);
      expect(h.liveReads, 0);
      expect(h.container.exists(appDocsDirProvider), isFalse);
      expect(h.container.exists(settingsRepositoryProvider), isFalse);
      expect(h.container.exists(activeLoanCountsProvider), isFalse);
    });
  }

  testWidgets('a successfully read empty library may still be published', (
    tester,
  ) async {
    final h = _Harness();
    final result = await h.publish(tester);

    expect(result, isA<PublishSuccess>());
    expect(h.states.last.requireValue, same(result));
    expect(h.api.commits, hasLength(1));
    final files = h.api.commits.single;
    final payload =
        jsonDecode(
              utf8.decode(
                files.firstWhere((file) => file.path == 'books.json').bytes,
              ),
            )
            as Map<String, dynamic>;
    expect(payload['books'], isEmpty);
    expect(files.map((file) => file.path), contains('index.html'));
    // R5 + plan SP1: the commit is persisted `deployed` and the publish
    // returns at once; the deferred check (handed over after the queue is
    // released) is what may upgrade it later.
    expect(h.manifest.current.state, PublishState.deployed);
    expect((result as PublishSuccess).pagesLive, isNull);
    expect(h.goingLive.tracked.single, same(result.verification));
  });

  testWidgets('plan SP1: the deferred check proves the record the commit '
      'saved; a failed publish starts none', (tester) async {
    final h = _Harness();
    final result = await h.publish(tester) as PublishSuccess;

    final request = h.goingLive.tracked.single;
    expect(request.headSha, h.manifest.current.headSha);
    expect(request.describes(h.manifest.current), isTrue);
    // The card reads the check by the very request the result carries.
    final check = h.container
        .read(publishGoingLiveProvider)
        .checkOf(result.verification!);
    expect(check?.outcome, isNull);
    // The publish read nothing back after its commit. Any later read is the
    // journal's own legacy migration (this harness starts without a
    // journal), which uses its fixed 'migrate' cache-buster.
    final afterCommit = h.verifier.cacheBusters.skip(h.readsBeforeCommit);
    expect(afterCommit, everyElement('migrate'));

    // A failure carries no request, so a second (failed) publish adds none.
    h.books.read = () async => left(const StorageFailure('private'));
    expect(await h.publish(tester), isA<PublishFailure>());
    expect(h.goingLive.tracked, hasLength(1));
  });

  testWidgets(
    'PublishMode.complete reaches the builder: a missing cover refuses instead '
    'of dropping it, and an incremental publish still succeeds',
    (tester) async {
      final h = _Harness();
      h.books.read = () async => right(const [
        CatalogueItem(id: 1, title: 'Coverless', coverUrl: 'covers/gone.jpg'),
      ]);

      // COMPLETE (a move or a whole-site replacement): a referenced cover with
      // no usable bytes is a typed failure BEFORE any write (R2).
      final complete = await h.publish(tester, mode: PublishMode.complete);
      expect(
        (complete as PublishFailure).reason,
        CatalogueSectionBuilder.missingCoverMessage,
      );
      expect(h.api.commits, isEmpty);
      expect(h.manifest.saves, 0);

      // INCREMENTAL (an ordinary publish) keeps the historical behaviour: the
      // cover degrades to the sanitized reference instead of blocking.
      expect(await h.publish(tester), isA<PublishSuccess>());
      expect(h.api.commits, hasLength(1));
    },
  );

  testWidgets('W3: a failed periodical read refuses the publish (no commit)', (
    tester,
  ) async {
    final h = _Harness();
    h.periodicals.read = () async => left(const StorageFailure('private'));
    final result = await h.publish(tester);

    expect((result as PublishFailure).reason, _safeReadFailure);
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  testWidgets('W3: series + issue wiring lands in books.json', (tester) async {
    final h = _Harness();
    h.books.read = () async => right(const [
      CatalogueItem(
        id: 2,
        title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
        details: IssueOf(periodicalUid: 'uid-1', issueNumber: 10),
      ),
    ]);
    h.periodicals.read = () async => right(const [
      PeriodicalSummary(
        periodical: Periodical(
          id: 7,
          periodicalUid: 'uid-1',
          title: 'Chandamama',
          notes: 'private series note',
        ),
        issueCount: 1,
      ),
    ]);
    expect(await h.publish(tester), isA<PublishSuccess>());
    final payload =
        jsonDecode(
              utf8.decode(
                h.api.commits.single
                    .firstWhere((file) => file.path == 'books.json')
                    .bytes,
              ),
            )
            as Map<String, dynamic>;
    final books = (payload['books'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(books.single['kind'], 'magazine-issue');
    expect(
      (books.single['issue'] as Map<String, dynamic>)['periodicalUid'],
      'uid-1',
    );
    expect(payload['periodicals'], hasLength(1));
    // The series' private fields never left the device.
    expect(
      utf8.decode(
        h.api.commits.single
            .firstWhere((file) => file.path == 'books.json')
            .bytes,
      ),
      isNot(contains('private series note')),
    );
  });

  group('item keys and availability (ADR 0019, plan S3)', () {
    testWidgets('every published item carries its key; the record is keyed', (
      tester,
    ) async {
      final h = _Harness();
      h.books.read = () async =>
          right(const [CatalogueItem(id: 5, title: 'Keyed')]);

      expect(await h.publish(tester), isA<PublishSuccess>());
      final commit = h.api.commits.single;
      final payload =
          jsonDecode(
                utf8.decode(
                  commit.firstWhere((file) => file.path == 'books.json').bytes,
                ),
              )
              as Map<String, dynamic>;
      final row = (payload['books'] as List).single as Map<String, dynamic>;
      // The harness salt names the key exactly like it names the covers.
      expect(
        row['key'],
        PublishItemKeys.keyFor(salt: const [1, 2, 3, 4], itemId: 5),
      );
      // Gate 7b's half in the record: this books.json is this phone's own,
      // keyed publish.
      expect(h.manifest.current.catalogueKeyed, isTrue);
      // The lane is not part of this build: nothing writes availability.json.
      expect(
        commit.map((file) => file.path),
        isNot(contains('availability.json')),
      );
    });

    testWidgets('an unreadable salt stops the publish before any write', (
      tester,
    ) async {
      final h = _Harness(saltAvailable: false);
      h.books.read = () async =>
          right(const [CatalogueItem(id: 5, title: 'Keyed')]);

      final result = await h.publish(tester);
      expect(
        (result as PublishFailure).reason,
        PublishItemKeys.saltUnavailableMessage,
      );
      expect(h.api.commits, isEmpty);
      expect(h.manifest.saves, 0);
    });

    testWidgets('until the lane ships, every publish asks for the removal', (
      tester,
    ) async {
      final h = _Harness();
      final request = await h.container
          .read(publishControllerProvider.notifier)
          .availability();
      expect(request.toNullable(), isA<AvailabilityRemoval>());
    });

    test('lane active: the Settings switch decides (plan S6)', () async {
      final on = _Harness(laneActivated: true);
      expect(
        (await on.container
                .read(publishControllerProvider.notifier)
                .availability())
            .toNullable(),
        isA<AvailabilityFromLoanCounts>(),
      );

      final off = _Harness(laneActivated: true)
        ..settings.autoPublishAvailability = false;
      expect(
        (await off.container
                .read(publishControllerProvider.notifier)
                .availability())
            .toNullable(),
        isA<AvailabilityRemoval>(),
      );
    });

    test('lane active + unreadable settings: the publish stops', () async {
      final h = _Harness(laneActivated: true)..settings.loadFails = true;
      final request = await h.container
          .read(publishControllerProvider.notifier)
          .availability();
      expect(
        (request.getLeft().toNullable()! as PublishReadFailure).message,
        PublishSnapshotBuilder.settingsUnavailableMessage,
      );
    });

    testWidgets('the GitHub events publish deletes a recorded file when the '
        'lane is off (plan S6, A.6 #60)', (tester) async {
      final h = _Harness(laneActivated: true)
        ..settings.autoPublishAvailability = false;
      h.manifest.current = const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'synthetic-commit',
        ownershipConfirmed: true,
        fileShas: {
          'index.html': 'i1',
          'books.json': 'b1',
          'availability.json': 'a1',
        },
        catalogueKeyed: true,
      );
      h.api.tree = {...h.manifest.current.fileShas};

      final pending = h.container
          .read(publishEventsControllerProvider.notifier)
          .publish();
      await tester.pump();
      await tester.pump(_settle);
      final result = await pending;

      expect(result, isA<PublishSuccess>());
      expect(h.api.deletions.single, contains('availability.json'));
      expect(h.manifest.current.shaFor('availability.json'), isNull);
      // Plan SP1: the events controller hands its commit's deferred check
      // over too, proven through events.json.
      final request = h.goingLive.tracked.single;
      expect(request, same((result as PublishSuccess).verification));
      expect(request.proof, PublishProofPath.eventsJson);
      expect(result.pagesLive, isNull);
    });

    testWidgets('lane active + known counts: the catalogue commit carries '
        'availability.json (AV8)', (tester) async {
      final h = _Harness(laneActivated: true, loanCounts: const {5: 1});
      h.books.read = () async =>
          right(const [CatalogueItem(id: 5, title: 'Keyed')]);

      final result = await h.publish(tester);

      expect(result, isA<PublishSuccess>());
      final paths = h.api.commits.single.map((file) => file.path);
      expect(paths, contains('availability.json'));
      expect(h.manifest.current.shaFor('availability.json'), isNotNull);
    });
  });

  testWidgets(
    'successful read preserves filtering and private-data redaction',
    (tester) async {
      final h = _Harness();
      h.books.read = () async => right(const [
        CatalogueItem(
          id: 1,
          title: 'Visible title',
          notes: 'private-note',
          location: 'private-shelf',
        ),
        CatalogueItem(id: 2, title: 'Removed title', removed: true),
      ]);
      expect(await h.publish(tester), isA<PublishSuccess>());
      final json = utf8.decode(
        h.api.commits.single
            .firstWhere((file) => file.path == 'books.json')
            .bytes,
      );
      expect(json, contains('Visible title'));
      expect(json, isNot(contains('Removed title')));
      expect(json, isNot(contains('private-')));
      expect(json, isNot(contains('availability')));
    },
  );

  testWidgets(
    'retry reads fresh data; a later failure preserves the last publish',
    (tester) async {
      final h = _Harness();
      h.books.read = () async => left(const StorageFailure('private-first'));
      expect(await h.publish(tester), isA<PublishFailure>());
      h.books.read = () async =>
          right(const [CatalogueItem(id: 1, title: 'Recovered')]);
      expect(await h.publish(tester), isA<PublishSuccess>());
      final saved = h.manifest.current;
      final savesAfterSuccess = h.manifest.saves;
      h.books.read = () async => left(const StorageFailure('private-second'));
      final result = await h.publish(tester);

      expect((result as PublishFailure).reason, _safeReadFailure);
      expect(h.states.last.requireValue, same(result));
      expect(h.books.reads, 3);
      expect(h.api.commits, hasLength(1));
      // The failure wrote nothing: the last successful record is untouched.
      expect(h.manifest.saves, savesAfterSuccess);
      expect(h.manifest.current, same(saved));
    },
  );

  for (final succeeds in [false, true]) {
    testWidgets('delayed read ($succeeds) gates all publish preparation', (
      tester,
    ) async {
      final h = _Harness();
      final read = Completer<Either<Failure, List<CatalogueItem>>>();
      h.books.read = () => read.future;
      final pending = h.container
          .read(publishControllerProvider.notifier)
          .publish();
      await tester.pump();
      expect(h.states.last.isLoading, isTrue);
      // The sealed target is resolved before the library read (R1/C3): that is
      // the one local credential read that precedes it. The TOKEN, the API and
      // the manifest all stay untouched while the read is pending.
      expect(h.credentials.reads, 1);
      expect(h.api.reads, 0);
      expect(h.api.commits, isEmpty);
      expect(h.container.exists(appDocsDirProvider), isFalse);
      read.complete(
        succeeds ? right([]) : left(const StorageFailure('private')),
      );
      await tester.pump();
      await tester.pump(_settle);
      final result = await pending;
      expect(result, succeeds ? isA<PublishSuccess>() : isA<PublishFailure>());
      expect(h.api.commits, hasLength(succeeds ? 1 : 0));
    });

    testWidgets(
      'unobserved publish stays alive until read completes ($succeeds)',
      (tester) async {
        final h = _Harness(observe: false);
        final read = Completer<Either<Failure, List<CatalogueItem>>>();
        h.books.read = () => read.future;
        final pending = h.container
            .read(publishControllerProvider.notifier)
            .publish();
        await tester.pump();
        expect(h.container.exists(publishControllerProvider), isTrue);
        read.complete(
          succeeds ? right([]) : left(const StorageFailure('private')),
        );
        await tester.pump();
        await tester.pump(_settle);
        expect(
          await pending,
          succeeds ? isA<PublishSuccess>() : isA<PublishFailure>(),
        );
        await tester.pump();
        expect(h.container.exists(publishControllerProvider), isFalse);
      },
    );
  }

  testWidgets('unexpected read exceptions still fail closed and end loading', (
    tester,
  ) async {
    final h = _Harness();
    final error = Exception('private-unexpected-detail');
    h.books.read = () async => throw error;
    final pending = h.container
        .read(publishControllerProvider.notifier)
        .publish();
    final assertion = expectLater(pending, throwsA(same(error)));
    await tester.pump();
    await assertion;
    // Flush Riverpod's zero-delay disposal timer before widget-test teardown.
    await tester.pump(Duration.zero);
    expect(h.states.last.hasError, isTrue);
    expect(h.states.last.isLoading, isFalse);
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  testWidgets('page shows a safe read failure and allows a successful retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    h.books.read = () async => left(const StorageFailure('private-db-detail'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: PublishPage()),
      ),
    );
    await tester.pumpAndSettle();
    final publish = find.widgetWithText(FilledButton, 'Publish catalogue now');
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(find.text('Publish failed: $_safeReadFailure'), findsOneWidget);
    expect(find.textContaining('private-db-detail'), findsNothing);
    expect(find.text('Your site'), findsNothing);
    expect(h.api.commits, isEmpty);
    expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);

    h.books.read = () async => right([]);
    await tester.tap(publish);
    await tester.pump();
    await tester.pump(_settle);
    await tester.pumpAndSettle();
    // Plan SP1: the card answers at commit time, then follows the deferred
    // check (product owner, 2026-11-02: a line that updates itself).
    expect(
      find.text('Published — going live (usually within a minute).'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
    h.goingLive.finish(
      h.goingLive.tracked.single,
      DeferredVerificationOutcome.live,
    );
    await tester.pumpAndSettle();
    expect(find.text('Published! Your site is live.'), findsOneWidget);
    expect(h.api.commits, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('a failed identity read refuses the whole publish', (
    tester,
  ) async {
    final h = _Harness();
    h.settings.identityFails = true;
    final result = await h.publish(tester);

    expect((result as PublishFailure).reason, 'Library identity unavailable');
    expect(result.reason, isNot(contains('private-mint-detail')));
    expect(h.api.commits, isEmpty);
    expect(h.manifest.saves, 0);
  });

  testWidgets(
    'SECURITY (M1): an unbuildable descriptor refuses the publish instead '
    'of silently deleting the published library.json',
    (tester) async {
      final h = _Harness();
      h.settings.identityMalformed = true; // stored ID is not a LibraryId
      // A library.json from an earlier run is live on the site.
      h.manifest.current = const PublishManifest(
        repo: 'me/lib',
        fileShas: {'books.json': 'old-books-sha', 'library.json': 'old-lib'},
      );

      final result = await h.publish(tester);

      expect((result as PublishFailure).reason, 'Library identity unavailable');
      expect(h.api.commits, isEmpty, reason: 'no commit — nothing deleted');
      expect(h.manifest.saves, 0);
    },
  );

  testWidgets(
    'SECURITY (M14): an unreadable network table refuses the publish with '
    'the real reason instead of publishing an empty member list',
    (tester) async {
      final h = _Harness(networkUnavailable: true);
      // A library.json with members is live on the site.
      h.manifest.current = const PublishManifest(
        repo: 'me/lib',
        fileShas: {'books.json': 'old-books-sha', 'library.json': 'old-lib'},
      );

      final result = await h.publish(tester);

      expect(
        (result as PublishFailure).reason,
        'Could not read your saved libraries. Nothing was published. '
        'Please try again.',
      );
      expect(h.api.commits, isEmpty, reason: 'no commit — members intact');
      expect(h.manifest.saves, 0);
      // The controller settled to a data state (not a dangling loading).
      expect(h.states.last.hasValue, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unchanged second publish reuses the live updatedAt and SKIPS the '
    'library.json upload (review Lows)',
    (tester) async {
      final h = _Harness();
      expect(await h.publish(tester), isA<PublishSuccess>());
      expect(await h.publish(tester), isA<PublishSuccess>());

      expect(h.api.commits, hasLength(2));
      bool libraryJsonUploaded(List<DesiredFile> commit) => commit.any(
        (f) => f.path == PublishLibraryUseCase.libraryJsonPath && f.upload,
      );
      expect(
        libraryJsonUploaded(h.api.commits[0]),
        isTrue,
        reason: 'the first publish writes the descriptor',
      );
      expect(
        libraryJsonUploaded(h.api.commits[1]),
        isFalse,
        reason: 'content unchanged ⇒ live timestamp reused ⇒ same blob sha',
      );

      // The two descriptor bytes are byte-identical even though the fake
      // clock moved a minute between publishes.
      List<int> descriptorBytes(List<DesiredFile> commit) =>
          committedBytes(commit, PublishLibraryUseCase.libraryJsonPath);
      final first = descriptorBytes(h.api.commits[0]);
      final second = descriptorBytes(h.api.commits[1]);
      expect(utf8.decode(second), utf8.decode(first));
      // The reused timestamp is the FIRST publish's — the candidate's fresh
      // one was replaced (the fake clock moved between publishes).
      final firstUpdatedAt =
          (jsonDecode(utf8.decode(first)) as Map<String, dynamic>)['updatedAt'];
      final secondUpdatedAt =
          (jsonDecode(utf8.decode(second))
              as Map<String, dynamic>)['updatedAt'];
      expect(secondUpdatedAt, firstUpdatedAt);
    },
  );

  testWidgets(
    'library.json rides along — fingerprint yes, raw library ID never',
    (tester) async {
      final h = _Harness();
      expect(await h.publish(tester), isA<PublishSuccess>());

      final descriptor = h.api.commits.single.firstWhere(
        (file) => file.path == 'library.json',
      );
      final json = utf8.decode(descriptor.bytes);
      // The published identity is the FINGERPRINT of the ID (D3) …
      expect(json, contains(LibraryFingerprint.of('a' * 32)));
      // … and the raw ID itself never appears in the published file.
      expect(json, isNot(contains('a' * 32)));
      // Sharing is off by default ⇒ no location block at all (D7).
      expect(json, isNot(contains('"location"')));
      // The descriptor points at the site being published.
      expect(json, contains('https://me.github.io/lib/'));
    },
  );

  testWidgets('isMember rows become library.json members (§5.5)', (
    tester,
  ) async {
    const memberFp =
        'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
    final h = _Harness();
    h.network.rows = [
      // A member with a fingerprint: listed.
      const NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'M Library',
        fingerprint: memberFp,
        source: NetworkSource.card,
        isMember: true,
        memberVerified: true,
      ),
      // A plain bookmark row (the default source): NOT listed.
      const NetworkLibrary(id: 2, siteUrl: 'https://b.github.io/y/', name: 'B'),
      // A member row without a fingerprint yet: cannot be listed (there is
      // nothing to match on) — stays out.
      const NetworkLibrary(
        id: 3,
        siteUrl: 'https://n.github.io/z/',
        source: NetworkSource.card,
        isMember: true,
      ),
      // memberOf (§5.5/§5.6-4): ONLY a CONFIRMED hub membership is published.
      const NetworkLibrary(
        id: 4,
        siteUrl: 'https://hub.github.io/h/',
        name: 'My Hub',
        membership: MembershipState.confirmed,
      ),
      // Pending and declined memberships never appear in the descriptor —
      // a membership is public only by the user's explicit choice.
      const NetworkLibrary(
        id: 5,
        siteUrl: 'https://maybe.github.io/h/',
        membership: MembershipState.pending,
      ),
      const NetworkLibrary(
        id: 6,
        siteUrl: 'https://nope.github.io/h/',
        membership: MembershipState.declined,
      ),
    ];
    expect(await h.publish(tester), isA<PublishSuccess>());

    final descriptor = h.api.commits.single.firstWhere(
      (file) => file.path == 'library.json',
    );
    final json =
        jsonDecode(utf8.decode(descriptor.bytes)) as Map<String, dynamic>;
    expect(json['members'], [
      {
        'fingerprint': memberFp,
        'siteUrl': 'https://m.github.io/x/',
        'name': 'M Library',
      },
    ]);
    expect(json['memberOf'], ['https://hub.github.io/h/']);
  });

  testWidgets(
    'SECURITY (L1): a member list over the wire cap REFUSES the publish — '
    'nothing uploaded, nothing deleted',
    (tester) async {
      // 201 members would encode a library.json every peer refuses in full
      // (decode truncates at 200 / rejects over 64 KiB) — the library would
      // silently vanish from the network behind a "Published!".
      final h = _Harness();
      h.network.rows = [
        for (var i = 0; i < 201; i++)
          NetworkLibrary(
            id: i + 1,
            siteUrl: 'https://m$i.github.io/',
            // Valid but DISTINCT 64-hex fingerprints (a real hub's members
            // never share one — and the fake table would not either).
            fingerprint: '${i.toRadixString(16).padLeft(8, '0')}${'f' * 56}',
            source: NetworkSource.card,
            isMember: true,
          ),
      ];
      h.manifest.current = const PublishManifest(
        repo: 'me/lib',
        fileShas: {'books.json': 'old-books-sha', 'library.json': 'old-lib'},
      );

      final result = await h.publish(tester);

      expect(
        (result as PublishFailure).reason,
        'Your published member list is too large. Remove some members in '
        'the Library network list, then publish again.',
      );
      expect(h.api.commits, isEmpty, reason: 'no commit — nothing uploaded');
      expect(h.manifest.saves, 0);
    },
  );
}

/// The bytes one committed file carried (the harness records every commit's
/// full desired-file list, uploaded or not).
List<int> committedBytes(List<DesiredFile> commit, String path) {
  for (final f in commit) {
    if (f.path == path) return f.bytes;
  }
  throw StateError('no $path in commit');
}

/// How far a test advances the fake clock after starting a publish: enough
/// for the pre-check of an earlier unconfirmed commit (3 polls, 2 s apart)
/// and Riverpod's zero-delay dispose timers. Since plan SP1 a GitHub publish
/// no longer waits for its own read-back.
const Duration _settle = Duration(seconds: 10);

/// Every side-effecting port is in memory; unexpected calls fail the test.
class _Harness {
  /// [networkUnavailable] makes the network repository provider fail the way
  /// the composition root does when the legacy-bookmarks migration cannot
  /// complete (review M14).
  _Harness({
    bool observe = true,
    bool networkUnavailable = false,
    bool saltAvailable = true,
    bool laneActivated = false,
    Map<int, int>? loanCounts,
  }) {
    // R6: the fake remote starts as what this phone recorded.
    api.tree = {...manifest.current.fileShas};
    api.head = manifest.current.headSha ?? api.head;
    container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => books),
        // W3: the controller also reads the series for books.json.
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        gitHubApiProvider.overrideWithValue(api),
        publishCredentialStoreProvider.overrideWithValue(credentials),
        cloudflareCredentialStoreProvider.overrideWithValue(
          InMemoryCloudflareCredentialStore(),
        ),
        publishCoverIdsProvider.overrideWithValue(
          PublishCoverIds(_Salt(saltAvailable ? const [1, 2, 3, 4] : null)),
        ),
        publishManifestStoreProvider.overrideWith((ref) async => manifest),
        // R33: the journal is in memory here. Without this override the real
        // prefs-backed store would be built, and a widget test has no
        // platform storage channel to answer it.
        publishHostStateStoreProvider.overrideWith((ref) async => hostState),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        if (networkUnavailable)
          networkRepositoryProvider.overrideWith(
            (ref) async =>
                throw const LegacyBookmarksMigrationException('StorageFailure'),
          )
        else
          networkRepositoryProvider.overrideWith((ref) async => network),
        eventsRepositoryProvider.overrideWith((ref) async => _Events()),
        // A handle only: no local covers in these tests, so no disk access.
        appDocsDirProvider.overrideWith((ref) async => Directory('.')),
        // M02: the real coversDir resolves through the active data generation
        // (which would CREATE `data/` under the docs dir above). Pin it so
        // this fixture keeps its no-disk-access promise.
        coversDirProvider.overrideWith((ref) async => 'covers'),
        activeLoanCountsProvider.overrideWith((ref) => loanCounts),
        availabilityLaneActivatedProvider.overrideWithValue(laneActivated),
        // The snapshot wiring resolves the poster-reader handle up front (the
        // builder is shared by every host). Stubbing it keeps this fixture's
        // no-disk-access promise intact.
        eventsPosterReaderProvider.overrideWith(
          (ref) async =>
              (_) async => null,
        ),
        // The events page template is a bundled asset; the events test only
        // needs some bytes.
        eventsHtmlFactoryProvider.overrideWithValue(
          ({required libraryName, required posters}) async =>
              utf8.encode('<html>events</html>'),
        ),
        viewerHtmlFactoryProvider.overrideWithValue(({
          required libraryName,
          required contact,
          required sharing,
        }) async {
          viewerBuilds++;
          return utf8.encode('<html></html>');
        }),
        remoteCoverFetcherProvider.overrideWithValue((_) async {
          remoteReads++;
          return null;
        }),
        publishedSiteVerifierProvider.overrideWithValue(verifier),
        // The pre-check of an unconfirmed commit reads through the structured
        // port (ADR 0019 Decision 10); it is the same in-memory site.
        publishedSiteReadVerifierProvider.overrideWithValue(verifier),
        // A clock that ticks a minute per read: two publishes never share a
        // timestamp, so an updatedAt-reuse test is deterministic.
        clockProvider.overrideWithValue(() => 1000 + (++_clockTicks * 60000)),
        // Plan SP1: the deferred check is recorded, not run (no 30 s timer).
        publishGoingLiveProvider.overrideWith(() => goingLive),
      ],
    );
    if (observe) {
      container.listen(
        publishControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
    }
    addTearDown(container.dispose);
  }

  int _clockTicks = 0;

  /// The in-memory live site. Routes by PATH like the real one: library.json
  /// serves the last committed descriptor (null before the first publish),
  /// anything else is the read-back poll for books.json.
  late final _Verifier verifier = _Verifier((path) async {
    liveReads++;
    if (api.commits.isEmpty) readsBeforeCommit++;
    if (api.commits.isEmpty) return null;
    final committed = api.commits.last;
    if (path == 'library.json') {
      for (final file in committed) {
        if (file.path == 'library.json') return file.bytes;
      }
      return null;
    }
    // An events commit carries events.json (and no books.json): serve the
    // committed file for its own path.
    for (final file in committed) {
      if (file.path == path) return file.bytes;
    }
    for (final file in committed) {
      if (file.path == 'books.json') return file.bytes;
    }
    return null;
  });
  final books = _Books();
  final periodicals = _Periodicals();
  final api = _Api();
  final credentials = _Credentials();
  final manifest = _Manifest();
  final hostState = _HostState();
  final settings = _Settings();
  final network = _Network();
  late final ProviderContainer container;
  final states = <AsyncValue<PublishResult?>>[];
  int viewerBuilds = 0;
  int remoteReads = 0;
  int liveReads = 0;

  /// Live reads made before the first commit existed.
  int readsBeforeCommit = 0;
  final goingLive = RecordingPublishGoingLive();

  Future<PublishResult> publish(
    WidgetTester tester, {
    PublishMode mode = PublishMode.incremental,
  }) async {
    final pending = container
        .read(publishControllerProvider.notifier)
        .publish(mode: mode);
    await tester.pump();
    await tester.pump(_settle);
    return pending;
  }
}

/// The publish salt. Every catalogue publish reads it since plan S3: it names
/// the covers AND gives every item its public key (ADR 0019 Decision 3).
/// With `saltAvailable: false` it fails like unreadable secure storage does
/// (a `PlatformException` is an `Exception`), so the publish must stop.
class _Salt implements PublishCoverSaltStore {
  _Salt([this._bytes]);

  final List<int>? _bytes;

  @override
  Future<List<int>> salt() async =>
      _bytes ?? (throw const FormatException('secure storage unreadable'));
}

class _Books implements CatalogueItemRepository {
  Future<Either<Failure, List<CatalogueItem>>> Function() read = () async =>
      right([]);
  int reads = 0;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() {
    reads++;
    return read();
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() {
    reads++;
    return read();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected book operation');
}

/// W3: the publish controller reads the series through `listAll`. Only that
/// method is answered; anything else is a bug in the wiring under test.
class _Periodicals implements PeriodicalRepository {
  Future<Either<Failure, List<PeriodicalSummary>>> Function() read = () async =>
      right(const []);
  int reads = 0;

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() {
    reads++;
    return read();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected periodical operation');
}

class _Settings implements SettingsRepository {
  /// Flipped by the identity-failure test: the publish must refuse rather
  /// than ship a descriptor without an honest fingerprint (fail closed).
  bool identityFails = false;

  /// Flipped by the M1 test: the repository hands back whatever is stored,
  /// and a malformed value must refuse the publish — not delete the
  /// published descriptor behind a "Published!".
  bool identityMalformed = false;

  /// The automatic availability switch (ADR 0019; default on).
  bool autoPublishAvailability = true;

  /// Makes the first settings load fail (an unreadable settings store).
  bool loadFails = false;

  @override
  Future<AppSettings> load() async {
    if (loadFails) throw const FileSystemException('synthetic');
    return AppSettings.defaults.copyWith(
      autoPublishAvailability: autoPublishAvailability,
    );
  }

  // The library.json descriptor needs the identity (docs/ARCHITECTURE.md §5.1), so
  // a publish now legitimately READS it through the controller's current().
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async {
    if (identityFails) return left(const StorageFailure('private-mint-detail'));
    return right(identityMalformed ? 'NOT-A-HEX-ID' : 'a' * 32);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings write');
}

class _Events implements EventsRepository {
  @override
  Future<EventsContent> loadForEditor() async => EventsContent.empty;

  @override
  Future<Either<Failure, EventsContent>> loadStrict() async =>
      right(EventsContent.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected event operation');
}

/// Read-back fake routed by the site-relative path. It answers both read
/// ports like the production adapter; a null answer is "unreadable".
class _Verifier implements PublishedSiteVerifier, PublishedSiteReadVerifier {
  _Verifier(this.answer);
  final Future<List<int>?> Function(String path) answer;
  final List<String?> cacheBusters = [];

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) {
    cacheBusters.add(cacheBuster);
    return answer(path);
  }

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    cacheBusters.add(cacheBuster);
    final body = await answer(path);
    return body == null
        ? const PublishedSiteReadUnreadable()
        : PublishedSiteReadBody(body);
  }
}

class _Credentials implements PublishCredentialStore {
  int reads = 0;

  @override
  Future<String?> token() async {
    reads++;
    return 'synthetic-test-token';
  }

  @override
  Future<String?> targetRepo() async {
    reads++;
    return 'me/lib';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected credential write');
}

/// In-memory host journal: records every write the publish path makes (R33).
class _HostState implements PublishHostStateStore {
  PublishHostState? stored;

  @override
  Either<Failure, PublishHostState?> load() => right(stored);

  @override
  Future<Either<Failure, Unit>> save(PublishHostState state) async {
    stored = state;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearUnreadable() async =>
      left(const ValidationFailure('readable'));
}

class _Manifest implements PublishManifestGateway {
  PublishManifest current = const PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    fileShas: {'books.json': 'old-books-sha'},
    coverUrlByBookId: {'1': 'covers/old.jpg'},
  );
  int loads = 0;
  int saves = 0;

  @override
  PublishManifest load() {
    loads++;
    return current;
  }

  @override
  Either<Failure, Unit> save(PublishManifest manifest) {
    saves++;
    current = manifest;
    return right(unit);
  }
}

class _Api implements GitHubApi {
  int reads = 0;
  final commits = <List<DesiredFile>>[];

  /// The paths each commit deleted, in order.
  final deletions = <List<String>>[];

  /// The fake remote branch: head + tree, updated by every successful commit
  /// so a second publish sees exactly what the first one wrote (R6).
  String head = 'synthetic-commit';
  Map<String, String> tree = const {};

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    reads++;
    return const PagesSite(
      sourceBranch: 'main',
      sourcePath: '/',
      isWorkflowBuild: false,
    );
  }

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    reads++;
    return GitHubTreeSnapshot(
      repo: '$owner/$repo',
      branch: branch,
      headSha: head,
      files: tree,
      truncated: false,
    );
  }

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
    Future<void> Function(String gitSha)? onBlobStored,
  }) async {
    final files = plan.files;
    // R6: never overwrite a head this publish was not built from.
    if (expectedHead != head) return const PublishCommitStale();
    commits.add(files);
    deletions.add(deletePaths);
    tree = {for (final f in files) f.path: f.gitSha};
    return PublishCommitSuccess(head, ['books.json']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected GitHub operation');
}

/// In-memory network rows: the publish controller reads the `isMember` ones
/// for library.json's members list (§5.5). No disk, no Drift.
class _Network implements NetworkRepository {
  List<NetworkLibrary> rows = const [];

  @override
  Future<List<NetworkLibrary>> loadAll() async => rows;
  @override
  Future<int> count() async => rows.length;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected network operation');
}
