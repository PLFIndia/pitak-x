/// Library list filter state (application layer, AGENTS.md §4/§7).
///
/// Why this is a provider and not a field on `LibraryController` (review
/// 2026-09-03, Blocker): the filter chips used to read
/// `ref.watch(libraryControllerProvider.notifier).languageFilter` — a plain
/// mutable field. Watching `.notifier` only rebuilds when the notifier
/// INSTANCE changes, never when a field on it mutates, so tapping a chip
/// filtered the list but the chip never showed as selected and "Clear" never
/// appeared. The user could not see or undo an active filter.
///
/// Riverpod's rule is "UI reacts to state only": the filter must BE state.
/// This tiny synchronous `Notifier` holds it; `LibraryController.build`
/// watches it (so the list re-queries automatically when it changes) and the
/// chips watch it (so they render the truth). One source, two readers, no
/// manual `refresh()` calls to keep in sync.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_filter_controller.g.dart';

/// The active language facet for the library list; null = all languages.
///
/// keepAlive: the chosen filter must survive navigating away from and back to
/// the Library screen (opening a book and returning must not silently reset
/// it), so it lives for the app session like the list's other view state.
@Riverpod(keepAlive: true)
class LibraryLanguageFilter extends _$LibraryLanguageFilter {
  @override
  String? build() => null;

  /// Sets (or clears, with null) the language filter. Blank strings count as
  /// "clear" so a stray empty chip label can never produce a filter that
  /// matches nothing.
  void set(String? language) {
    final trimmed = language?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Clears the filter.
  void clear() => state = null;
}
