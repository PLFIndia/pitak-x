import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_connection_section.dart';

import 'support/cloudflare_fakes.dart';

void main() {
  testWidgets('connects through real dialogs to a confirmed ready target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final graph = CloudflareSetupHarness();
    final container = ProviderContainer(
      overrides: [
        setupCloudflareSiteProvider.overrideWith((ref) async => graph.setup),
        cloudflareCredentialStoreProvider.overrideWithValue(graph.credentials),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CloudflareConnectionSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cloudflare Workers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Cloudflare'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Cloudflare Workers'), findsOneWidget);

    final raw = cloudflareTestToken().use((value) => value);
    await tester.enterText(find.byType(TextField), raw);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Cloudflare account'), findsOneWidget);

    await tester.tap(find.text('Library account'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Worker'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'new-worker');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to publish'), findsOneWidget);
    expect(
      find.textContaining('https://new-worker.library.workers.dev/'),
      findsOneWidget,
    );
    expect(graph.credentials.record?.status.target, isNotNull);
    expect(graph.api.deployCalls, 0);
    expect(container.read(passphraseEntryVisibilityProvider), 0);
    expect(find.text(raw), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreadable record can be forgotten through its dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final graph = CloudflareSetupHarness(connection: cloudflareTestConnection())
      ..credentials.failRead = true;
    final container = ProviderContainer(
      overrides: [
        setupCloudflareSiteProvider.overrideWith((ref) async => graph.setup),
        cloudflareCredentialStoreProvider.overrideWithValue(graph.credentials),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CloudflareConnectionSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare Workers'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forget Cloudflare connection'));
    await tester.pumpAndSettle();
    expect(find.text('Forget Cloudflare connection?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(graph.credentials.clears, 0);

    graph.credentials.failRead = false;
    await tester.tap(find.text('Forget Cloudflare connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget connection'));
    await tester.pumpAndSettle();

    expect(graph.credentials.clears, 1);
    expect(graph.credentials.record, isNull);
    expect(find.text('Connect Cloudflare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
