/// The ONE place the app's visual theme is defined.
///
/// Why a dedicated file (architecture.md A6 "adjust colours via the theme —
/// one place"; B2 "pin the five screens users see most"): `main.dart`, the
/// golden tests and the accessibility-contrast tests must all render the
/// *same* colours, or the tests pin a UI nobody ships. Keeping both
/// `ThemeData` here means a seed-colour change is one diff that every one of
/// those tests sees.
///
/// Pure presentation code: no state, no IO — safe to use from tests directly.
library;

import 'package:flutter/material.dart';

/// Light and dark [ThemeData] for Pitaka (Material 3, indigo seed).
abstract final class AppTheme {
  /// Seed every scheme derives from. Change it here and nowhere else.
  static const Color seedColor = Colors.indigo;

  /// Light theme (the default when the user has not chosen one).
  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    useMaterial3: true,
  );

  /// Dark theme, same seed with [Brightness.dark].
  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
