import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_journal_reset_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/presentation/widgets/publish_card.dart';

import 'support/cloudflare_fakes.dart';

final class _FakePublishController extends PublishController {
  _FakePublishController(this.results);

  final List<PublishResult> results;
  final List<({PublishReplacementSummary? confirmation, bool verificationOnly})>
  calls = [];

  @override
  FutureOr<PublishResult?> build() => null;

  @override
  Future<PublishResult> publish({
    PublishMode mode = PublishMode.incremental,
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    calls.add((confirmation: confirmation, verificationOnly: verificationOnly));
    state = const AsyncLoading();
    final result = results.length > 1 ? results.removeAt(0) : results.first;
    state = AsyncData(result);
    return result;
  }
}

/// Like [_FakePublishController], but each call waits for its own future, so
/// a test can look at the card WHILE a publish is running. It sets loading
/// exactly as the real controller does (Riverpod keeps the previous value).
final class _InFlightPublishController extends PublishController {
  _InFlightPublishController(this.results);

  final List<Future<PublishResult>> results;

  @override
  FutureOr<PublishResult?> build() => null;

  @override
  Future<PublishResult> publish({
    PublishMode mode = PublishMode.incremental,
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    state = const AsyncLoading();
    final result = await results.removeAt(0);
    state = AsyncData(result);
    return result;
  }
}

void main() {
  final target = cloudflareTestConnection().status.target!;
  final status = PublishSiteStatus(
    activeHost: PublishHost.cloudflare,
    target: target,
    verifiedSiteUrl: target.siteUrl,
    setupMessage: null,
  );

  PublishReplacementSummary summary({
    int items = 2,
    int posters = 1,
    String? digest,
  }) => PublishReplacementSummary(
    target: target,
    requestedSection: PublishRequestedSection.catalogue,
    digest: digest ?? 'a' * 64,
    catalogueItemCount: items,
    posterCount: posters,
    availabilityOmitted: false,
    remoteAnchor: const CloudflareRemoteAnchor(
      workerExists: true,
      markerKind: CloudflareMarkerKind.absent,
    ),
    reason: PublishReplacementReason.unknownRemoteState,
  );

  Future<void> pump(
    WidgetTester tester,
    PublishController controller, {
    PublishSiteStatus? site,
    PublishJournalReset? reset,
  }) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publishSiteStatusProvider.overrideWith((ref) async => site ?? status),
          publishControllerProvider.overrideWith(() => controller),
          if (reset != null)
            publishJournalResetProvider.overrideWith(() => reset),
        ],
        child: const MaterialApp(home: Scaffold(body: PublishCard())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders active Cloudflare target and journal-verified address', (
    tester,
  ) async {
    await pump(tester, _FakePublishController([]));

    expect(find.text('Active host: Cloudflare Workers'), findsOneWidget);
    expect(find.textContaining('Configured target:'), findsOneWidget);
    expect(find.text(target.siteUrl), findsWidgets);
    expect(find.text('Publish catalogue now'), findsOneWidget);
  });

  testWidgets('publish intent and verified-live result reach the card', (
    tester,
  ) async {
    final controller = _FakePublishController([
      PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const ['books.json'],
        pagesLive: true,
      ),
    ]);
    await pump(tester, controller);

    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(1));
    expect(controller.calls.single.verificationOnly, isFalse);
    expect(find.text('Published! Your site is verified live.'), findsOneWidget);
  });

  testWidgets('replacement cancel performs no confirmation or remote command', (
    tester,
  ) async {
    final controller = _FakePublishController([
      PublishReplacementRequired(summary(items: 0, posters: 0)),
    ]);
    await pump(tester, controller);

    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    expect(find.text('Replace your Cloudflare site?'), findsOneWidget);
    expect(find.text('Your catalogue has 0 items'), findsOneWidget);
    expect(find.text('Your events page will be empty'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(1));
    expect(find.text('Review site replacement'), findsOneWidget);
  });

  testWidgets('replacement confirmation re-enters with the reviewed digest', (
    tester,
  ) async {
    final required = PublishReplacementRequired(summary());
    final controller = _FakePublishController([
      required,
      PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const [],
        pagesLive: true,
      ),
    ]);
    await pump(tester, controller);

    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace the site'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(2));
    expect(controller.calls.last.confirmation, same(required.summary));
    expect(find.text('Published! Your site is verified live.'), findsOneWidget);
  });

  // Real host, 2026-10-30 (row 12): for about a minute after confirming a
  // recreate, the card still said "Review site replacement" / "Review the
  // replacement before publishing." while the confirmed publish deployed and
  // verified. Riverpod keeps the previous value during AsyncLoading, so the
  // card must not render it while a run is in flight.
  testWidgets('while a confirmed publish runs, the card says Publishing… and '
      'never the review it just confirmed', (tester) async {
    final required = PublishReplacementRequired(summary());
    final inFlight = Completer<PublishResult>();
    final controller = _InFlightPublishController([
      Future.value(required),
      inFlight.future,
    ]);
    await pump(tester, controller);

    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace the site'));
    // The confirmed run is in flight: its spinner never settles, so pump once.
    await tester.pump();

    expect(find.text('Publishing…'), findsOneWidget);
    expect(find.text('Review site replacement'), findsNothing);
    expect(
      find.text('Review the replacement before publishing.'),
      findsNothing,
    );

    inFlight.complete(
      PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const [],
        pagesLive: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Published! Your site is verified live.'), findsOneWidget);
    expect(find.text('Publishing…'), findsNothing);
  });

  testWidgets('a changed digest opens a new replacement review instead of '
      'deploying stale bytes', (tester) async {
    final first = PublishReplacementRequired(summary(items: 1));
    final second = PublishReplacementRequired(
      summary(items: 3, digest: 'b' * 64),
    );
    final controller = _FakePublishController([first, second]);
    await pump(tester, controller);

    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace the site'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(2));
    expect(find.text('Replace your Cloudflare site?'), findsOneWidget);
    expect(find.textContaining('catalogue (3 items)'), findsOneWidget);
  });

  testWidgets('unverified deployment offers deploy-free verification retry', (
    tester,
  ) async {
    final controller = _FakePublishController([
      PublishSuccess(pagesUrl: target.siteUrl, uploadedPaths: const []),
    ]);
    await pump(tester, controller);
    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry verification'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(2));
    expect(controller.calls.last.verificationOnly, isTrue);
  });

  testWidgets('a deploy-free verification says Verified, not Published!', (
    tester,
  ) async {
    final controller = _FakePublishController([
      PublishSuccess(
        pagesUrl: target.siteUrl,
        uploadedPaths: const [],
        pagesLive: true,
        newDeployment: false,
      ),
    ]);
    await pump(tester, controller);
    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Verified: your live site matches this phone’s last publish.'),
      findsOneWidget,
    );
    expect(find.textContaining('Published!'), findsNothing);
  });

  testWidgets('an uncertain deploy offers the deploy-free check', (
    tester,
  ) async {
    final controller = _FakePublishController([
      const PublishFailure(
        'Cloudflare did not confirm the deployment, so the site may or may '
        'not have changed. Tap Retry verification to check before publishing '
        'again.',
        canRetryVerification: true,
      ),
    ]);
    await pump(tester, controller);
    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry verification'));
    await tester.pumpAndSettle();

    expect(controller.calls, hasLength(2));
    expect(controller.calls.last.verificationOnly, isTrue);
  });

  testWidgets('a failure no check can fix offers no Retry verification', (
    tester,
  ) async {
    final controller = _FakePublishController([
      const PublishFailure(
        'The live Cloudflare site does not match this phone’s last publish. '
        'Publish to review a whole-site replacement.',
      ),
    ]);
    await pump(tester, controller);
    await tester.tap(find.text('Publish catalogue now'));
    await tester.pumpAndSettle();

    expect(find.text('Retry verification'), findsNothing);
  });

  testWidgets('an unreadable publishing record offers a confirmed reset', (
    tester,
  ) async {
    final reset = _FakeReset();
    await pump(
      tester,
      _FakePublishController([]),
      site: const PublishSiteStatus(
        activeHost: null,
        target: null,
        verifiedSiteUrl: null,
        setupMessage: 'Cloudflare setup on this phone can’t be read.',
        journalUnreadable: true,
      ),
      reset: reset,
    );

    expect(find.text('Reset publishing record'), findsOneWidget);
    await tester.tap(find.text('Reset publishing record'));
    await tester.pumpAndSettle();
    expect(find.text('Reset the publishing record?'), findsOneWidget);
    await tester.tap(find.text('Keep the record'));
    await tester.pumpAndSettle();
    expect(reset.calls, 0);

    await tester.tap(find.text('Reset publishing record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset record'));
    await tester.pumpAndSettle();
    expect(reset.calls, 1);
    expect(find.textContaining('Publishing record reset'), findsOneWidget);
  });

  testWidgets('a readable record never shows the reset action', (tester) async {
    await pump(tester, _FakePublishController([]));
    expect(find.text('Reset publishing record'), findsNothing);
  });
}

final class _FakeReset extends PublishJournalReset {
  int calls = 0;

  @override
  FutureOr<void> build() {}

  @override
  Future<Either<Failure, Unit>> resetUnreadable() async {
    calls++;
    return right(unit);
  }
}
