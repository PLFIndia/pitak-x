import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/presentation/widgets/basic_info_tab.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';

/// Widget tests for the location-sharing control (docs/ARCHITECTURE.md §3 network/§5.4):
/// the 3-way opt-in under the GPS field, its first-read seeding, that Save
/// persists the enum token, and that view mode shows a read-only row (no
/// disabled control — a11y contrast).
void main() {
  SegmentedButton<LocationSharing> control(WidgetTester tester) =>
      tester.widget(find.byType(SegmentedButton<LocationSharing>));

  Future<void> pumpTab(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    // Tall surface so the whole tab lays out on-screen.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BasicInfoTab())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterEditMode(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh install defaults to "Not shared" (default off)', (
    tester,
  ) async {
    await pumpTab(tester);
    // View mode: a read-only row, no segmented control yet.
    expect(find.byType(SegmentedButton<LocationSharing>), findsNothing);
    expect(find.text('Not shared'), findsOneWidget);

    await enterEditMode(tester);
    expect(control(tester).selected, {LocationSharing.off});
    expect(find.text('Approximate (~1 km)'), findsOneWidget);
    expect(find.text('Exact'), findsOneWidget);
  });

  testWidgets('first-read rule: an existing GPS value seeds "Exact"', (
    tester,
  ) async {
    // D7 behaviour preservation: users who already published a pin see the
    // switch where their published behaviour actually is.
    await pumpTab(tester, prefs: {'publish_contact_gps': '12.97, 77.59'});
    expect(find.text('Exact'), findsOneWidget);
    await enterEditMode(tester);
    expect(control(tester).selected, {LocationSharing.exact});
  });

  testWidgets('Edit → Approximate → Save persists the token', (tester) async {
    await pumpTab(tester, prefs: {'publish_contact_gps': '12.9876, 77.5946'});
    await enterEditMode(tester);
    expect(control(tester).onSelectionChanged, isNotNull);

    await tester.tap(find.text('Approximate (~1 km)'));
    await tester.pumpAndSettle();
    expect(control(tester).selected, {LocationSharing.approximate});

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('publish_location_sharing'), 'approximate');
    // Back in view mode, the saved choice stays visible as the value row.
    expect(find.byType(SegmentedButton<LocationSharing>), findsNothing);
    expect(find.text('Approximate (~1 km)'), findsOneWidget);
  });

  testWidgets('the caution text mentions the network map', (tester) async {
    await pumpTab(tester);
    expect(find.textContaining('Library network map'), findsOneWidget);
    expect(find.text('Share my location on the network map'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines (view and edit mode)', (
    tester,
  ) async {
    await pumpTab(tester);
    await expectMeetsA11yGuidelines(tester);
    await enterEditMode(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
