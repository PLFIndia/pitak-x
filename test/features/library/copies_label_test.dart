/// `CopiesLabel`: "**Copies:** 2 · 1 out" — hidden for one copy, the out
/// count in the Not-available red, words for screen readers, and readable on
/// both places it is drawn (the list surface and the grid's cover pill).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/theme/availability_colors.dart';
import 'package:pitaka/features/library/presentation/widgets/copies_label.dart';

import '../../support/a11y.dart';

const _minimum = 4.5;

void main() {
  Widget host(ThemeData theme, {required int copies, required int out}) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => CopiesLabel(
              copyCount: copies,
              copiesOut: out,
              style: Theme.of(context).textTheme.labelLarge,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );

  /// The spans of the rendered label, in order.
  List<TextSpan> spans(WidgetTester tester) {
    final text = tester.widget<Text>(find.byType(Text));
    return (text.textSpan! as TextSpan).children!.cast<TextSpan>();
  }

  testWidgets('a single copy shows nothing', (tester) async {
    await tester.pumpWidget(host(AppTheme.light, copies: 1, out: 1));
    expect(find.byType(Text), findsNothing);
    expect(CopiesLabel.isVisibleFor(1), isFalse);
    expect(CopiesLabel.isVisibleFor(2), isTrue);
  });

  testWidgets('no copies out (or vault locked): just the count', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppTheme.light, copies: 2, out: 0));
    expect(find.text('Copies: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('2 copies'), findsOneWidget);
  });

  testWidgets('"Copies:" is bold; the out count is the Not-available red', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppTheme.light, copies: 2, out: 1));
    expect(find.text('Copies: 2 · 1 out'), findsOneWidget);
    final parts = spans(tester);
    expect(parts.first.text, 'Copies: ');
    expect(parts.first.style?.fontWeight, FontWeight.w700);
    final outSpan = parts.last;
    expect(outSpan.text, '1 out');
    expect(
      outSpan.style?.color,
      AvailabilityColors.unavailableForeground(Brightness.light),
    );
  });

  testWidgets('screen readers hear words, not symbols', (tester) async {
    await tester.pumpWidget(host(AppTheme.light, copies: 2, out: 1));
    expect(find.bySemanticsLabel('2 copies, 1 on loan'), findsOneWidget);
  });

  testWidgets('more loans than copies is shown as-is (bad data is visible)', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppTheme.light, copies: 2, out: 3));
    expect(find.text('Copies: 2 · 3 out'), findsOneWidget);
  });

  testWidgets('dark theme uses the dark red', (tester) async {
    await tester.pumpWidget(host(AppTheme.dark, copies: 3, out: 2));
    expect(
      spans(tester).last.style?.color,
      AvailabilityColors.unavailableForeground(Brightness.dark),
    );
  });

  // Where the label is drawn: the list row (onSurfaceVariant on the list
  // surface) and the grid's cover pill (onSurface on
  // surfaceContainerHighest). The red "N out" must be readable on both.
  for (final MapEntry(key: name, value: theme) in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final scheme = theme.colorScheme;
    final red = AvailabilityColors.unavailableForeground(theme.brightness);
    group('$name theme contrast ≥ $_minimum:1', () {
      test('list: label on surface', () {
        final ratio = contrastRatio(scheme.onSurfaceVariant, scheme.surface);
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });
      test('list: "out" on surface', () {
        final ratio = contrastRatio(red, scheme.surface);
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });
      test('grid pill: label on surfaceContainerHighest', () {
        final ratio = contrastRatio(
          scheme.onSurface,
          scheme.surfaceContainerHighest,
        );
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });
      test('grid pill: "out" on surfaceContainerHighest', () {
        final ratio = contrastRatio(red, scheme.surfaceContainerHighest);
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });
    });
  }
}
