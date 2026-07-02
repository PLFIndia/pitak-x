/// UI-facing library controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the Library screen drives: on build it loads all
/// books (newest first); `onQueryChanged` swaps the list to FTS5 matches.
/// Queries are debounced (120ms) to mirror the Kotlin query flow and
/// avoid hammering SQLite on every keystroke. The repository returns
/// `Either<Failure, _>`; a left becomes `AsyncError(Failure)` so the UI can
/// render a safe message (raw exception text is never surfaced).
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_controller.g.dart';

/// Debounce window before a typed query hits SQLite (matches Kotlin's 120ms).
const _searchDebounce = Duration(milliseconds: 120);

/// Loads and searches the library book list for the presentation layer.
@riverpod
class LibraryController extends _$LibraryController {
  Timer? _debounce;
  String _query = '';
  String? _languageFilter;
  BookSort _sort = BookSort.recentlyAdded;

  @override
  FutureOr<List<Book>> build() async {
    // Cancel any in-flight debounce when the provider is disposed.
    ref.onDispose(() => _debounce?.cancel());
    // WATCH the persisted sort (narrowed with select, §8): changing it in
    // Settings rebuilds this provider and re-sorts the list immediately.
    // A ref.read here would freeze the sort until an unrelated refresh.
    _sort = ref.watch(
      settingsControllerProvider.select(
        (s) => s.maybeWhen(
          data: (settings) => settings.librarySort,
          orElse: () => BookSort.recentlyAdded,
        ),
      ),
    );
    return _load(_query);
  }

  /// The current query text (so the UI can render the field without owning it).
  String get query => _query;

  /// The active language filter (null = all languages).
  String? get languageFilter => _languageFilter;

  /// Sets (or clears, with null) the language filter, then refreshes.
  Future<void> setLanguageFilter(String? language) async {
    _languageFilter = language;
    await refresh();
  }

  /// Updates the query and refreshes the list after a short debounce. An empty
  /// query restores the full list. Each keystroke resets the timer.
  void onQueryChanged(String query) {
    _query = query;
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () async {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _load(query));
    });
  }

  /// Reloads the list for the active query (used after external mutations).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(_query));
  }

  /// Soft-deletes book [id] (stays visible-but-inert), then refreshes.
  ///
  /// Fail closed (§5): a repository Left becomes `AsyncError(Failure)` — a
  /// failed write must never refresh the list as if it succeeded.
  Future<void> remove(int id) async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final result = await repo.markRemoved(
      id,
      DateTime.now().millisecondsSinceEpoch,
    );
    await result.fold(
      (failure) async => state = AsyncError(failure, StackTrace.current),
      (_) => refresh(),
    );
  }

  /// Clears the soft-delete flag on book [id], then refreshes. Fails closed
  /// like [remove].
  Future<void> restoreRemoved(int id) async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final result = await repo.restoreRemoved(id);
    await result.fold(
      (failure) async => state = AsyncError(failure, StackTrace.current),
      (_) => refresh(),
    );
  }

  /// Fetches books for [query], applying the persisted sort (watched in
  /// [build]) and the active language filter. A non-empty query takes the FTS
  /// path (then the filter is applied in Dart); a blank query uses the
  /// sorted+filtered repository query. The repository's `Either` is unwrapped
  /// into a value or a thrown `Failure`, which Riverpod's
  /// `build`/`AsyncValue.guard` turn into `AsyncError`.
  Future<List<Book>> _load(String query) async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final sort = _sort;
    final lang = _languageFilter;

    if (query.trim().isEmpty) {
      final result = await repo.query(sort: sort, language: lang);
      return result.fold(
        (failure) =>
            // ignore: only_throw_errors, Riverpod surfaces errors via throw
            throw failure,
        (books) => books,
      );
    }
    // Search path: FTS5 matches, then narrow by language in Dart (the FTS
    // query doesn't carry the facet).
    final result = await repo.search(query);
    return result.fold(
      (failure) =>
          // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
          throw failure,
      (books) => lang == null || lang.trim().isEmpty
          ? books
          : books
                .where(
                  (b) => (b.language ?? '').toLowerCase() == lang.toLowerCase(),
                )
                .toList(),
    );
  }
}
