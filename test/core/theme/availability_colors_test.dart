/// Pins the availability tag colours: each foreground must reach WCAG's
/// small-text 4.5:1 on its own pill background AND on the real surfaces of
/// both `AppTheme`s (the shelf-location line paints the "not available"
/// foreground straight onto the list surface, not onto a pill).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/theme/availability_colors.dart';

import '../../support/a11y.dart';

const _minimum = 4.5;

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    final brightness = theme.brightness;
    final scheme = theme.colorScheme;

    group('$name theme', () {
      test('Available text on its pill ≥ $_minimum:1', () {
        final ratio = contrastRatio(
          AvailabilityColors.availableForeground(brightness),
          AvailabilityColors.availableBackground(brightness),
        );
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });

      test('Not available text on its pill ≥ $_minimum:1', () {
        final ratio = contrastRatio(
          AvailabilityColors.unavailableForeground(brightness),
          AvailabilityColors.unavailableBackground(brightness),
        );
        expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
      });

      for (final MapEntry(key: surfaceName, value: surface) in <String, Color>{
        'surface': scheme.surface,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
      }.entries) {
        test('Not available text directly on $surfaceName ≥ $_minimum:1', () {
          final ratio = contrastRatio(
            AvailabilityColors.unavailableForeground(brightness),
            surface,
          );
          expect(ratio, greaterThanOrEqualTo(_minimum), reason: '$ratio');
        });
      }

      test('Available and Not available are visibly different', () {
        expect(
          AvailabilityColors.availableForeground(brightness),
          isNot(AvailabilityColors.unavailableForeground(brightness)),
        );
        expect(
          AvailabilityColors.availableBackground(brightness),
          isNot(AvailabilityColors.unavailableBackground(brightness)),
        );
      });
    });
  }
}
