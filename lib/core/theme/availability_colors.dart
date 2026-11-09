/// Brightness-aware colours for the *Available* / *Not available* tags.
///
/// Why one shared class: the tag appears in three places — the in-app
/// viewer's badges (network feature), the library list's "Not available"
/// pill and the shelf-location line (library feature). Before this file each
/// place picked its own container colour, so *Available* and *Not available*
/// looked identical. The published web site already fixed the vocabulary
/// (`assets/publish/index.html`, `.avail-available` / `.avail-out`): green
/// for Available, red for Not available. These values mirror those hexes so
/// the app and the site tell the same story.
///
/// Same pattern as `ProviderStatusColors` (publish feature): plain static
/// functions of [Brightness], no `ThemeExtension`, because every caller
/// already has a `Theme.of(context)` and the pairs never vary per screen.
///
/// Every foreground sits at ≥ 4.5:1 on its own background and on the real
/// surface colours of `AppTheme`; `test/core/theme/availability_colors_test.dart`
/// pins that in both themes.
library;

import 'package:flutter/material.dart';

/// Colours for the coarse availability tags.
abstract final class AvailabilityColors {
  /// Text colour of the *Available* tag (web: `#1b5e20` / dark `#7fdf95`).
  static Color availableForeground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF7FDF95)
      : const Color(0xFF1B5E20);

  /// Fill colour of the *Available* tag.
  static Color availableBackground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF0F2E16)
      : const Color(0xFFE8F5E9);

  /// Text colour of the *Not available* tag (web: `#b00020` / dark
  /// `#ff8a80`). Also used for the shelf-location line when the item is
  /// not available, so the two signals agree.
  static Color unavailableForeground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFFF8A80)
      : const Color(0xFFB00020);

  /// Fill colour of the *Not available* tag.
  static Color unavailableBackground(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF3B1515)
      : const Color(0xFFFFEBEE);
}
