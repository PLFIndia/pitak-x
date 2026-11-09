/// `PublishedItemBadges`: the two availability tags must be told apart by
/// colour as well as by words (the web site's green / red pair), and both
/// must stay readable in either theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/theme/availability_colors.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_badges.dart';

import '../../../support/a11y.dart';

void main() {
  Widget host(ThemeData theme, PublishedCatalogueItem item) => MaterialApp(
    theme: theme,
    home: Scaffold(body: PublishedItemBadges(item: item)),
  );

  /// The tinted container painted behind [label].
  Container pillOf(WidgetTester tester, String label) =>
      tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)),
      );

  Color pillColor(WidgetTester tester, String label) =>
      (pillOf(tester, label).decoration! as BoxDecoration).color!;

  Color textColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  const available = PublishedCatalogueItem(
    sourceIndex: 0,
    title: 'In',
    kind: PublishedItemKind.book,
    availability: PublishedAvailability.available,
    availabilitySource: PublishedAvailabilitySource.catalogue,
  );
  const out = PublishedCatalogueItem(
    sourceIndex: 1,
    title: 'Out',
    kind: PublishedItemKind.book,
    availability: PublishedAvailability.out,
    availabilitySource: PublishedAvailabilitySource.catalogue,
  );

  for (final MapEntry(key: name, value: theme) in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final brightness = theme.brightness;

    group('$name theme', () {
      testWidgets('Available is the green tag', (tester) async {
        await tester.pumpWidget(host(theme, available));
        expect(
          pillColor(tester, 'Available'),
          AvailabilityColors.availableBackground(brightness),
        );
        expect(
          textColor(tester, 'Available'),
          AvailabilityColors.availableForeground(brightness),
        );
        await expectMeetsTextContrast(tester);
      });

      testWidgets('Not available is the red tag', (tester) async {
        await tester.pumpWidget(host(theme, out));
        expect(
          pillColor(tester, 'Not available'),
          AvailabilityColors.unavailableBackground(brightness),
        );
        expect(
          textColor(tester, 'Not available'),
          AvailabilityColors.unavailableForeground(brightness),
        );
        await expectMeetsTextContrast(tester);
      });

      testWidgets('the two tags never share a colour', (tester) async {
        await tester.pumpWidget(host(theme, available));
        final availableBg = pillColor(tester, 'Available');
        await tester.pumpWidget(host(theme, out));
        expect(pillColor(tester, 'Not available'), isNot(availableBg));
      });
    });
  }

  testWidgets('a classifier badge keeps the neutral tone', (tester) async {
    const aged = PublishedCatalogueItem(
      sourceIndex: 2,
      title: 'Aged',
      kind: PublishedItemKind.book,
      ageGroup: AgeGroup.above6,
    );
    await tester.pumpWidget(host(AppTheme.light, aged));
    expect(
      pillColor(tester, 'Above 6'),
      AppTheme.light.colorScheme.surfaceContainerHighest,
    );
  });
}
