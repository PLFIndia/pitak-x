/// S35 banner widget tests: renders only the two active statuses, zero-height
/// silence otherwise, and its two actions (dismiss / restart) reach the
/// controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/presentation/widgets/app_update_banner.dart';

import 'fake_app_update_service.dart';

void main() {
  late FakeAppUpdateService service;

  Widget host() => ProviderScope(
    overrides: [appUpdateServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            AppUpdateBanner(),
            Expanded(child: Text('library content')),
          ],
        ),
      ),
    ),
  );

  setUp(() => service = FakeAppUpdateService());
  tearDown(() => service.dispose());

  testWidgets('silent (zero-height) when there is nothing to do', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('library content'), findsOneWidget);
  });

  testWidgets('silent when ineligible (fdroid/desktop/tests)', (tester) async {
    service.eligible = false;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets(
    'a background download shows the progress banner; Hide dismisses',
    (tester) async {
      service.availability = AppUpdateAvailability.available;
      await tester.pumpWidget(host());
      // NOT pumpAndSettle: the banner's progress spinner animates forever, so
      // "settled" is never reached. The fake service completes in microtasks;
      // a few explicit frames land every state change.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        find.text('Update downloading in the background…'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle(); // spinner gone → settles again
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );

  testWidgets(
    'a finished download offers Restart, which completes the update',
    (tester) async {
      service.availability = AppUpdateAvailability.downloaded;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.text('Update ready — restart the app to install it.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(service.completeCalls, 1);
    },
  );

  testWidgets('Later dismisses the restart offer for the session', (
    tester,
  ) async {
    service.availability = AppUpdateAvailability.downloaded;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });
}
