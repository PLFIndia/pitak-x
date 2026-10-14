/// Bookmarks-feature DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: persistence for other libraries' published sites — a
/// non-secret flat list in shared_preferences (no Drift table/migration).
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/infrastructure/prefs_bookmarks_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookmarks_providers.g.dart';

/// Library-bookmarks persistence (other libraries' published sites). Non-secret
/// flat list in shared_preferences — no Drift table/migration.
@riverpod
Future<BookmarksRepository> bookmarksRepository(
  BookmarksRepositoryRef ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsBookmarksRepository(prefs);
}
