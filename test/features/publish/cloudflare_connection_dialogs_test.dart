import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_name_dialogs.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_token_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_verification_dialog.dart';

import 'support/cloudflare_fakes.dart';

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container,
  Future<void> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets('token entry is masked and protected while visible', (
    tester,
  ) async {
    await _open(tester, container, showCloudflareTokenDialog);
    expect(container.read(passphraseEntryVisibilityProvider), 1);
    expect(container.read(screenCaptureProtectedProvider), isTrue);
    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);
    // L13: a pasted API token is not a login credential. The field is
    // explicitly excluded from autofill (so password managers do not offer to
    // save it) and from the keyboard's personalised learning.
    expect(field().autofillHints, isNull);
    expect(field().enableIMEPersonalizedLearning, isFalse);

    await tester.tap(find.byTooltip('Show token'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide token'));
    await tester.pump();
    expect(field().obscureText, isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(passphraseEntryVisibilityProvider), 0);
  });

  testWidgets('invalid token shows fixed non-echoing copy and stays open', (
    tester,
  ) async {
    var popped = false;
    await _open(tester, container, (context) async {
      await showCloudflareTokenDialog(context);
      popped = true;
    });
    await tester.enterText(find.byType(TextField), 'not a token <secret>');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, CloudflareErrorMessages.invalidToken);
    expect(field.decoration?.errorText, isNot(contains('secret')));
    expect(find.text('Connect Cloudflare Workers'), findsOneWidget);
    expect(popped, isFalse);
  });

  testWidgets('valid token is trimmed and returned directly', (tester) async {
    CloudflareApiToken? result;
    final raw = cloudflareTestToken().use((value) => value);
    await _open(tester, container, (context) async {
      result = await showCloudflareTokenDialog(context);
    });
    await tester.enterText(find.byType(TextField), '  $raw  ');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.kind, CloudflareApiTokenKind.user);
  });

  test('external token URL is the fixed least-privilege HTTPS template', () {
    expect(cloudflareTokenCreationUri.scheme, 'https');
    expect(cloudflareTokenCreationUri.host, 'dash.cloudflare.com');
    expect(cloudflareTokenCreationUri.path, '/');
    expect(
      cloudflareTokenCreationUri.queryParameters['to'],
      '/:account/api-tokens',
    );
    expect(cloudflareTokenCreationUri.queryParameters['accountId'], isNull);
    final permissions =
        cloudflareTokenCreationUri.queryParameters['permissionGroupKeys'];
    expect(permissions, contains('workers_scripts'));
    expect(permissions, contains('edit'));
    expect(permissions, isNot(contains('workers_kv_storage')));
    expect(
      cloudflareTokenCreationUri.queryParameters['name'],
      'Pitak Library Publishing',
    );
  });

  testWidgets('a hostile account name is replaced, not shown (L14)', (
    tester,
  ) async {
    CloudflareAccountChoice? result;
    final second = CloudflareAccountId.tryParse(
      'fedcba9876543210fedcba9876543210',
    )!;
    await _open(tester, container, (context) async {
      result = await showCloudflareAccountDialog(
        context,
        accounts: [
          CloudflareAccount(
            id: CloudflareAccountId.tryParse(cloudflareTestAccountId)!,
            name: 'Evil\u202Eaccount',
          ),
          CloudflareAccount(id: second, name: 'Second account'),
        ],
      );
    });

    expect(find.text('Account …cdef'), findsOneWidget);
    expect(find.text('Second account'), findsOneWidget);
    expect(find.text('Enter Account ID manually'), findsOneWidget);
    expect(find.textContaining('\u202E'), findsNothing);
    expect(result, isNull, reason: 'nothing was chosen yet');
  });

  testWidgets('Account ID dialog validates without echoing bad input', (
    tester,
  ) async {
    String? result;
    await _open(tester, container, (context) async {
      result = await showCloudflareManualAccountDialog(context);
    });
    await tester.enterText(find.byType(TextField), 'bad <id>');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, CloudflareErrorMessages.invalidAccount);
    expect(field.decoration?.errorText, isNot(contains('<id>')));
    expect(result, isNull);

    await tester.enterText(find.byType(TextField), cloudflareTestAccountId);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, cloudflareTestAccountId);
  });

  testWidgets(
    'verification consent discloses marker-only and replacement scope',
    (tester) async {
      var accepted = false;
      await _open(tester, container, (context) async {
        accepted = await showCloudflareVerificationDialog(
          context,
          workerName: 'existing-worker',
          workerExists: true,
        );
      });

      expect(find.textContaining('ALL assets currently on it'), findsOneWidget);
      expect(
        find.textContaining('No catalogue, events, or library.json'),
        findsOneWidget,
      );
      expect(find.textContaining('pitak-publish.json'), findsOneWidget);
      await tester.tap(find.text('Deploy verification marker'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    },
  );

  testWidgets('existing-Worker replacement consent can be declined', (
    tester,
  ) async {
    var accepted = true;
    await _open(tester, container, (context) async {
      accepted = await showCloudflareWorkerReplacementDialog(
        context,
        workerName: 'existing-worker',
        verificationRequested: false,
      );
    });

    expect(find.textContaining('replaces ALL assets'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
  });
}
