/// Settings → Data → Publishing: the automatic availability switch (ADR 0019,
/// plan P3/C.8). Hidden until the lane ships (plan S8); on by default.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const switchTitle = 'Update availability on my site automatically';

  Future<void> pumpData(
    WidgetTester tester, {
    required bool activated,
    ThemeData? theme,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final tmp = Directory.systemTemp.createTempSync('pitak_publishing_group');
    addTearDown(() => tmp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coversDirProvider.overrideWith((ref) async => tmp.path),
          availabilityLaneActivatedProvider.overrideWithValue(activated),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const SettingsPage(initialTab: SettingsTab.data),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hidden while this build does not run the lane (plan S8)', (
    tester,
  ) async {
    await pumpData(tester, activated: false);
    expect(find.text('Publishing'), findsNothing);
    expect(find.text(switchTitle), findsNothing);
    expect(find.text('Create backup'), findsOneWidget);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('on by default; turning it off is saved ($name)', (
      tester,
    ) async {
      await pumpData(tester, activated: true, theme: theme);

      expect(find.text('Publishing'), findsOneWidget);
      final tile = find.widgetWithText(SwitchListTile, switchTitle);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_publish_availability'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a saved "off" shows as off', (tester) async {
    await pumpData(
      tester,
      activated: true,
      prefs: {'auto_publish_availability': false},
    );
    final tile = find.widgetWithText(SwitchListTile, switchTitle);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });
}
