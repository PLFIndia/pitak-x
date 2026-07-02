/// Maps the domain [AppThemeMode] to Flutter's [ThemeMode] (presentation).
///
/// The domain layer must stay pure Dart (AGENTS.md §3.1), so it defines its
/// own [AppThemeMode]; this one-liner is the only place the two meet.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Presentation-side bridge to Flutter's [ThemeMode].
extension AppThemeModeFlutterX on AppThemeMode {
  /// The Flutter [ThemeMode] this domain value renders as.
  ThemeMode toThemeMode() => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
