/// Bookmarks controller (application layer, AGENTS.md §4).
///
/// Loads + mutates the saved library bookmarks. URL/label validation lives in
/// the [LibraryBookmark]/[BookmarkUrl] domain; this controller orchestrates
/// persistence and exposes the list as an [AsyncValue].
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookmarks_controller.g.dart';

/// Loads + mutates the user's library bookmarks.
@riverpod
class BookmarksController extends _$BookmarksController {
  @override
  Future<List<LibraryBookmark>> build() async {
    final repo = await ref.read(bookmarksRepositoryProvider.future);
    return repo.load();
  }

  /// Validates [label]/[url] and adds a bookmark. Returns true on success,
  /// false when the URL is not an accepted Pages link or the label is invalid.
  Future<bool> add({required String label, required String url}) async {
    final bookmark = LibraryBookmark.create(label: label, url: url);
    if (bookmark == null) return false;
    final repo = await ref.read(bookmarksRepositoryProvider.future);
    final result = await repo.add(bookmark);
    return result.match((_) => false, (list) {
      state = AsyncData(list);
      return true;
    });
  }

  /// Removes the bookmark at [index]. Returns true on success.
  Future<bool> removeAt(int index) async {
    final repo = await ref.read(bookmarksRepositoryProvider.future);
    final result = await repo.removeAt(index);
    return result.match((_) => false, (list) {
      state = AsyncData(list);
      return true;
    });
  }
}
