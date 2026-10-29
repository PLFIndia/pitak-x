import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

import '../../support/a11y.dart';
import 'support/cloudflare_fakes.dart';

Widget _app(CloudflareConnectionUi ui, {VoidCallback? onForget}) => MaterialApp(
  home: Scaffold(
    body: CloudflareTile(
      ui: ui,
      onConnect: () {},
      onContinue: () {},
      onDisconnect: () {},
      onForgetConnection: onForget ?? () {},
    ),
  ),
);

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text('Cloudflare Workers'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an unreadable record shows the explanation and a Forget action',
    (tester) async {
      var forgotten = 0;
      await tester.pumpWidget(
        _app(
          const CloudflareConnectionUi(
            phase: CloudflareConnectionPhase.unreadable,
          ),
          onForget: () => forgotten++,
        ),
      );
      await _expand(tester);

      expect(find.textContaining('can’t be read'), findsOneWidget);
      expect(find.textContaining('share link are not changed'), findsOneWidget);
      await tester.tap(find.text('Forget Cloudflare connection'));
      expect(forgotten, 1);
      // No Connect/Disconnect/Continue action is offered while unreadable.
      expect(find.text('Connect Cloudflare'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    },
  );

  test('derives all five provider configuration states', () {
    expect(
      cloudflareProviderConfig(CloudflareConnectionStatus.empty),
      ProviderConfig.notConfigured,
    );
    expect(
      cloudflareProviderConfig(
        cloudflareTestConnection(
          withAccount: false,
          withSubdomain: false,
          withWorker: false,
        ).status,
      ),
      ProviderConfig.partial,
    );
    expect(
      cloudflareProviderConfig(
        cloudflareTestConnection(confirmed: false).status,
      ),
      ProviderConfig.addressNotConfirmed,
    );
    expect(
      cloudflareProviderConfig(cloudflareTestConnection().status),
      ProviderConfig.readyToPublish,
    );
    expect(
      cloudflareProviderConfig(
        cloudflareTestConnection(writeConfirmed: true).status,
      ),
      ProviderConfig.configured,
    );
  });

  testWidgets('candidate copy never presents an unverified address as live', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CloudflareConnectionUi(
          status: cloudflareTestConnection(confirmed: false).status,
        ),
      ),
    );
    expect(find.text('Address not confirmed yet'), findsOneWidget);
    await _expand(tester);

    expect(find.textContaining('Candidate:'), findsOneWidget);
    expect(
      find.textContaining('not used for sharing or publishing'),
      findsOneWidget,
    );
    expect(find.textContaining('Confirmed address:'), findsNothing);
  });

  testWidgets('confirmed target is ready but is not claimed to be live', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(CloudflareConnectionUi(status: cloudflareTestConnection().status)),
    );
    expect(find.text('Ready to publish'), findsOneWidget);
    await _expand(tester);

    expect(find.textContaining('Confirmed address:'), findsOneWidget);
    expect(
      find.text('A confirmed address is not necessarily live yet.'),
      findsOneWidget,
    );
    expect(find.text('Finish Cloudflare setup'), findsOneWidget);
  });

  testWidgets('displays a recorded token expiry when supplied', (tester) async {
    final status = CloudflareConnection.verifiedToken(
      cloudflareTestToken(),
      tokenExpiresOn: DateTime.utc(2027, 1, 2, 12),
    ).status;
    await tester.pumpWidget(_app(CloudflareConnectionUi(status: status)));
    await _expand(tester);
    expect(find.text('Token expires: 2027-01-02'), findsOneWidget);
  });

  testWidgets('working phase disables connection actions', (tester) async {
    await tester.pumpWidget(
      _app(
        const CloudflareConnectionUi(phase: CloudflareConnectionPhase.working),
      ),
    );
    await tester.tap(find.text('Cloudflare Workers'));
    // A working spinner never settles by design; advance the expansion only.
    await tester.pump(const Duration(milliseconds: 300));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Connect Cloudflare'),
    );
    expect(button.onPressed, isNull);
  });

  // S11 smoke (2026-10-29): on one line the name and the status fought for a
  // phone's width and both were cut off ("Cloudflare Wor…").
  testWidgets('the status sits below the name and neither is truncated on a '
      '360 dp phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        CloudflareConnectionUi(
          status: cloudflareTestConnection(confirmed: false).status,
        ),
      ),
    );

    final name = find.text('Cloudflare Workers');
    final status = find.text('Address not confirmed yet');
    expect(
      tester.getRect(status).top,
      greaterThanOrEqualTo(tester.getRect(name).bottom),
    );
    // The test font's square glyphs are far wider than a real phone font, so
    // the name may wrap here; what must never happen is an ellipsis.
    for (final text in [name, status]) {
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
    }
  });

  testWidgets('expanded tile survives 320px and larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: _app(
          CloudflareConnectionUi(
            status: cloudflareTestConnection(confirmed: false).status,
          ),
        ),
      ),
    );
    await _expand(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(_app(const CloudflareConnectionUi()));
    await _expand(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
