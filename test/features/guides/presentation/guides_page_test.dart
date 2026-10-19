import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/presentation/pages/guide_page.dart';
import 'package:pitaka/features/guides/presentation/pages/guides_page.dart';

import '../../../support/a11y.dart';

void main() {
  Future<void> pumpIndex(WidgetTester tester) async {
    // Phone width, the app's real theme (the a11y contrast check must see
    // the colours that ship). 1200 dp tall so all five cards are built: the
    // list measures ≈ 930 dp under the test font, more than a phone screen.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const GuidesPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the app bar title, the intro line and five cards in the '
      'approved order', (tester) async {
    await pumpIndex(tester);

    expect(find.text('How Pitak works'), findsOneWidget);
    expect(find.textContaining('Short guides, one per job.'), findsOneWidget);

    const titles = [
      'Put your catalogue online',
      'Put your library on the map',
      'Backup, restore, export, import',
      'Lending and the borrowers vault',
      'Hubs, members and library cards',
    ];
    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // Top-to-bottom order on screen matches the catalog order.
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.byType(ListTile), findsNWidgets(5));
  });

  testWidgets('every card is at least 48 dp tall', (tester) async {
    await pumpIndex(tester);
    for (final tile in find.byType(ListTile).evaluate()) {
      expect(
        tester.getSize(find.byWidget(tile.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('tapping a card pushes GuidePage for that guide', (tester) async {
    await pumpIndex(tester);

    await tester.tap(find.text('Put your catalogue online'));
    await tester.pumpAndSettle();

    final page = tester.widget<GuidePage>(find.byType(GuidePage));
    expect(page.guide.id, GuideId.publish);
    // The guide's own app bar title is now showing; the index is behind it.
    expect(find.text('Put your catalogue online'), findsOneWidget);
    expect(find.text('How Pitak works'), findsNothing);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await pumpIndex(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
