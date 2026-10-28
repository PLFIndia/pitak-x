import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
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
  );

  Future<void> pump(
    WidgetTester tester,
    _FakePublishController controller,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publishSiteStatusProvider.overrideWith((ref) async => status),
          publishControllerProvider.overrideWith(() => controller),
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
}
