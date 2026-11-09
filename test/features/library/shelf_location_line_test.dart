/// `ShelfLocationLine`: hidden when blank, bold, red only when the item is
/// not available, dimmed when removed, otherwise the theme's text colour —
/// in both themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/theme/availability_colors.dart';
import 'package:pitaka/features/library/presentation/widgets/shelf_location_line.dart';

import '../../support/a11y.dart';

void main() {
  Widget host(
    ThemeData theme, {
    required String? location,
    ShelfLocationTone tone = ShelfLocationTone.normal,
  }) => MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Builder(
        builder: (context) => ShelfLocationLine(
          location: location,
          tone: tone,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ),
  );

  Text lineText(WidgetTester tester) => tester.widget<Text>(find.text('A3'));

  group('ShelfLocationTone.of', () {
    test('removed wins over unavailable (never red when removed)', () {
      expect(
        ShelfLocationTone.of(removed: true, unavailable: true),
        ShelfLocationTone.removed,
      );
      expect(
        ShelfLocationTone.of(removed: true, unavailable: false),
        ShelfLocationTone.removed,
      );
    });

    test('unavailable, else normal', () {
      expect(
        ShelfLocationTone.of(removed: false, unavailable: true),
        ShelfLocationTone.unavailable,
      );
      expect(
        ShelfLocationTone.of(removed: false, unavailable: false),
        ShelfLocationTone.normal,
      );
    });
  });

  testWidgets('renders nothing for a null location', (tester) async {
    await tester.pumpWidget(host(AppTheme.light, location: null));
    expect(find.byType(Text), findsNothing);
    expect(find.byIcon(Icons.shelves), findsNothing);
  });

  testWidgets('renders nothing for a blank location', (tester) async {
    await tester.pumpWidget(host(AppTheme.light, location: '   '));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('trims the location and shows it bold with the shelf icon', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppTheme.light, location: '  A3  '));
    expect(find.text('A3'), findsOneWidget);
    expect(find.byIcon(Icons.shelves), findsOneWidget);
    expect(lineText(tester).style?.fontWeight, FontWeight.w600);
  });

  testWidgets('exposes the full meaning to screen readers', (tester) async {
    await tester.pumpWidget(host(AppTheme.light, location: 'A3'));
    expect(find.bySemanticsLabel('Shelf location: A3'), findsOneWidget);
  });

  for (final MapEntry(key: name, value: theme) in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    group('$name theme', () {
      testWidgets('available item uses the ordinary text colour', (
        tester,
      ) async {
        await tester.pumpWidget(host(theme, location: 'A3'));
        expect(lineText(tester).style?.color, theme.colorScheme.onSurface);
        await expectMeetsTextContrast(tester);
      });

      testWidgets('not-available item uses the Not available red', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(theme, location: 'A3', tone: ShelfLocationTone.unavailable),
        );
        expect(
          lineText(tester).style?.color,
          AvailabilityColors.unavailableForeground(theme.brightness),
        );
        await expectMeetsTextContrast(tester);
      });

      testWidgets('removed item is dimmed like its title, still readable', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(theme, location: 'A3', tone: ShelfLocationTone.removed),
        );
        expect(
          lineText(tester).style?.color,
          theme.colorScheme.onSurfaceVariant,
        );
        await expectMeetsTextContrast(tester);
      });
    });
  }
}
