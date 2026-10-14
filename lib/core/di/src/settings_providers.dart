/// Settings DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the non-secret settings repository (theme, library
/// identity, sort, publish contact info). The `SettingsController` state
/// notifier keeps its own `@riverpod` file in the feature's application
/// layer; this module only binds the repository it persists through.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_providers.g.dart';

/// Non-secret settings persistence (theme, library identity, sort).
@riverpod
Future<SettingsRepository> settingsRepository(SettingsRepositoryRef ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsSettingsRepository(prefs);
}
