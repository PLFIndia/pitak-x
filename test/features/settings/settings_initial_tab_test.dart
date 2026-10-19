/// `SettingsPage.initialTab`: a caller (the "How Pitak works" guides) can open
/// Settings directly on a named tab. Same page setup as
/// `backup_copy_truth_test.dart`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester, Widget page) async {
    SharedPreferences.setMockInitialValues({});
    // Sync IO: async file APIs never complete under the test's FakeAsync zone.
    final tmp = Directory.systemTemp.createTempSync('pitak_settings_tab');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // Tall surface: the tabs are lazy ListViews; tiles must be in the
    // viewport to be built at all.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // LibraryLogo (Appearance tab) resolves covers via this provider;
          // point it at a temp dir so the page builds without path_provider.
          coversDirProvider.overrideWith((ref) async => tmp.path),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('default opens on Appearance', (tester) async {
    await pumpSettings(tester, const SettingsPage());

    // Appearance content is visible; Data content is not built yet.
    expect(find.text('Library name'), findsOneWidget);
    expect(find.text('Create backup'), findsNothing);
  });

  testWidgets('initialTab: data opens straight on the Data tab', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      const SettingsPage(initialTab: SettingsTab.data),
    );

    // No tap on the "Data" tab: the backup tile is there from the first frame.
    expect(find.text('Create backup'), findsOneWidget);
    expect(find.text('Restore backup'), findsOneWidget);
    expect(find.text('Library name'), findsNothing);
  });

  testWidgets('initialTab: security opens straight on the Security tab', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      const SettingsPage(initialTab: SettingsTab.security),
    );

    expect(find.text('Require biometric to open Pitak'), findsOneWidget);
    expect(find.text('Create backup'), findsNothing);
  });

  test('SettingsTab order matches the TabBar order', () {
    // The enum index IS the tab index; a reorder here must be deliberate.
    expect(SettingsTab.values, [
      SettingsTab.appearance,
      SettingsTab.data,
      SettingsTab.security,
    ]);
  });
}
