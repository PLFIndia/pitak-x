/// Dependency-injection providers (AGENTS.md §4: Riverpod codegen is the DI
/// container — no GetIt, no service locators).
///
/// The non-secret Drift database and the repositories/use cases over it are
/// wired here. The encrypted vault is reached through the Rust FFI core via
/// [vaultRepository]; the vault key never enters Dart.
library;

// S3: providers live in per-feature modules under `src/`; this file imports
// the modules its remaining declarations reference AND re-exports all of
// them, so every call site keeps importing `core/di/providers.dart`.
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/vault_providers.dart';
import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';
import 'package:pitaka/features/app_update/infrastructure/play_app_update_service.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/infrastructure/prefs_bookmarks_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:pitaka/core/di/src/backup_providers.dart';
export 'package:pitaka/core/di/src/database_providers.dart';
export 'package:pitaka/core/di/src/events_providers.dart';
export 'package:pitaka/core/di/src/import_export_providers.dart';
export 'package:pitaka/core/di/src/library_providers.dart';
export 'package:pitaka/core/di/src/lookup_providers.dart';
export 'package:pitaka/core/di/src/platform_providers.dart';
export 'package:pitaka/core/di/src/publish_providers.dart';
export 'package:pitaka/core/di/src/settings_providers.dart';
export 'package:pitaka/core/di/src/vault_providers.dart';
export 'package:pitaka/core/di/src/wishlist_providers.dart';

part 'providers.g.dart';

/// Library-bookmarks persistence (other libraries' published sites). Non-secret
/// flat list in shared_preferences — no Drift table/migration.
@riverpod
Future<BookmarksRepository> bookmarksRepository(
  BookmarksRepositoryRef ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsBookmarksRepository(prefs);
}

/// The Play in-app update seam (S35). The real service gates itself to
/// Android + the `play` applicationId (the fdroid flavor has no Play listing
/// and stays inert) and degrades to silence on every platform failure.
/// Overridden with a fake in tests.
@riverpod
AppUpdateService appUpdateService(AppUpdateServiceRef ref) =>
    const PlayAppUpdateService(appInfo: MethodChannelAppInfo());
