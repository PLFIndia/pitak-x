/// The name a NEW catalogue row is attributed to (presentation layer).
///
/// This function stood, line for line, in four forms (the book form, the
/// other-item form, the magazine-title form and the issue form). It lives
/// here once, so the four cannot drift apart and the two forms near their
/// size limit have room for the "Discard changes?" guard (review finding
/// P4-M1: a move only, nothing behaves differently).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// The maintainer name from settings, or null when it is unset or blank, or
/// while the settings are not loaded. Only used to attribute newly added
/// rows; an edit keeps the name the row already has.
///
/// Call it from a handler (a Save tap), not while building: it reads the
/// settings once and does not watch them.
String? maintainerStampOf(WidgetRef ref) {
  final name = ref
      .read(settingsControllerProvider)
      .maybeWhen(data: (s) => s.maintainerName, orElse: () => '')
      .trim();
  return name.isEmpty ? null : name;
}
