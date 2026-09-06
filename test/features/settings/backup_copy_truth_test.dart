/// M06a copy guard: the Settings "Create backup" subtitle must not claim the
/// `.pitabak` archive is fully encrypted — only the borrowers vault inside it
/// is (astra-review.md M06). This widget test would have caught the old
/// "Full encrypted .pitabak archive" label.
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

  testWidgets('backup subtitle states only the vault is encrypted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Sync IO: async file APIs never complete under the test's FakeAsync zone.
    final tmp = Directory.systemTemp.createTempSync('pitak_m06a');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // Tall surface: the Data tab is a lazy ListView; the backup tile must be
    // in the viewport to be built at all.
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
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // The backup entry lives on the Data tab.
    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();

    // The false assurance must be gone…
    expect(find.textContaining('Full encrypted'), findsNothing);
    // …and the subtitle must say what is actually encrypted.
    expect(
      find.textContaining('only the borrowers vault inside is encrypted'),
      findsOneWidget,
    );
  });
}
