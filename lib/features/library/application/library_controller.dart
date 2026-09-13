/// UI-facing library controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the Library screen drives. Its state is a
/// [LibraryWindow]: the rows loaded so far for the current intent (search
/// text + persisted sort + language chip), whether more exist, and whether
/// the next page is in flight. Queries are debounced (120ms) to mirror the
/// Kotlin query flow and avoid hammering SQLite on every keystroke. The
/// repository returns `Either<Failure, _>`; a left on the FIRST page becomes
/// `AsyncError(Failure)` so the UI can render a safe message (raw exception
/// text is never surfaced).
///
/// ## Windows, not the catalogue (N10-d part 2, astra-review.md N10)
///
/// The controller reads ONE page (`libraryPageSize` rows) on build and
/// appends the next page on `loadMore` as the user nears the end of the
/// list. The repository produces the final order, filter and window inside
/// SQLite (part 1 + 2), so the controller never sorts, filters or slices.
///
/// Two kinds of reload, decided by comparing the new [LibraryQuery] with the
/// last one (user decision S30, D2-b):
///
///  - **Same intent, data changed** (a remove, a rename, an import — every
///    write path calls `refresh` or invalidates this provider): reload the
///    rows the user had already scrolled to, in ONE statement, so the list
///    does not jump back to the top.
///  - **Different intent** (sort changed, chip tapped, new search text): a
///    genuinely new list — start again at the first page.
///
/// The depth survives an `invalidate` because Riverpod keeps the SAME
/// notifier instance across rebuilds of a live provider (only a full dispose
/// — no listeners — recreates it), so `_lastQuery`/`_loadedDepth` are plain
/// fields.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_controller.g.dart';

/// Debounce window before a typed query hits SQLite (matches Kotlin's 120ms).
const _searchDebounce = Duration(milliseconds: 120);

/// Loads and pages the library book list for the presentation layer.
@riverpod
class LibraryController extends _$LibraryController {
  Timer? _debounce;
  String _query = '';
  String? _languageFilter;
  BookSort _sort = BookSort.recentlyAdded;

  /// The intent the current rows belong to; null before the first build.
  LibraryQuery? _lastQuery;

  /// How many rows the user has loaded for [_lastQuery] (≥ one page once
  /// anything loaded). A same-intent reload re-reads this many rows (D2-b).
  int _loadedDepth = libraryPageSize;

  /// N05: every new load intent (build, refresh, query change) bumps this;
  /// a completion publishes its result ONLY if it still belongs to the
  /// newest revision. Cancelling the debounce timer is not enough — a query
  /// already running in SQLite cannot be cancelled, and its late result must
  /// not overwrite the answer to a newer query. [loadMore] runs under the
  /// revision it started with, so a late second page of an OLD list is
  /// dropped instead of being appended to the NEW one.
  int _revision = 0;

  /// The in-flight [loadMore], so concurrent calls (a fast fling fires many
  /// scroll notifications) collapse into one read.
  Future<void>? _loadingMore;

  @override
  FutureOr<LibraryWindow> build() async {
    // Cancel any in-flight debounce when the provider is disposed.
    ref.onDispose(() => _debounce?.cancel());
    // A rebuild (sort/language change, invalidation) supersedes any read
    // still in flight — including a pending loadMore.
    _supersede();
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
    // WATCH the language facet the same way: it is real provider state (see
    // library_filter_controller.dart), so a chip tap rebuilds this list AND
    // the chips from one source of truth.
    _languageFilter = ref.watch(libraryLanguageFilterProvider);
    return _loadHead(_intent(_query));
  }

  /// The current query text (so the UI can render the field without owning it).
  String get query => _query;

  /// Updates the query and refreshes the list after a short debounce. An empty
  /// query restores the full list. Each keystroke resets the timer AND bumps
  /// the revision, so an older in-flight query can never land last (N05).
  void onQueryChanged(String query) {
    _query = query;
    final rev = _supersede();
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () async {
      state = const AsyncLoading();
      final loaded = await AsyncValue.guard(() => _loadHead(_intent(query)));
      if (rev == _revision) state = loaded; // stale completions are dropped
    });
  }

  /// Reloads the rows the user has already scrolled to, for the active intent
  /// (used after external mutations). Same-intent by construction, so the
  /// depth is kept (D2-b).
  Future<void> refresh() async {
    final rev = _supersede();
    state = const AsyncLoading();
    final loaded = await AsyncValue.guard(() => _loadHead(_intent(_query)));
    if (rev == _revision) state = loaded;
  }

  /// Fetches the next page and appends it. No-op when nothing is loaded yet,
  /// when the store said there is no more, or while a previous call is still
  /// running (returns that call's future). A failed page keeps the rows
  /// already shown and clears the in-flight flag so the user can scroll
  /// again to retry — a list the user is looking at is never blanked into an
  /// error for a page they have not seen yet.
  Future<void> loadMore() {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || state.isLoading) {
      return Future.value();
    }
    return _loadingMore ??= _loadMore(current);
  }

  Future<void> _loadMore(LibraryWindow current) async {
    final rev = _revision;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    final repo = await ref.read(bookRepositoryProvider.future);
    final result = await repo.page(
      _intent(_query),
      limit: libraryPageSize,
      offset: current.books.length,
    );
    // N05 extension: a newer intent has taken over — [_supersede] already
    // cleared `_loadingMore` and the new load owns the state. Drop this page.
    if (rev != _revision) return;
    _loadingMore = null;
    // A write failed while this page was in flight (`remove`/`restoreRemoved`
    // set AsyncError without a new revision): keep that error visible rather
    // than paint data over it (§5 fail closed).
    if (state.hasError) return;
    final latest = state.valueOrNull ?? current;
    state = AsyncData(
      result.fold((_) => latest.copyWith(isLoadingMore: false), (page) {
        final books = List<Book>.unmodifiable([...latest.books, ...page.items]);
        _loadedDepth = books.length;
        return LibraryWindow(books: books, hasMore: page.hasMore);
      }),
    );
  }

  /// Starts a new load intent: bumps the N05 revision so every read still in
  /// flight (first page OR a `loadMore` page) is dropped when it lands, and
  /// forgets the pending `loadMore` so the next call can start a fresh one.
  /// Returns the new revision for the caller to compare against.
  int _supersede() {
    _revision++;
    _loadingMore = null;
    return _revision;
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

  /// The whole read intent as one value: [text] plus the sort and facet
  /// watched in [build]. Normalised by `LibraryQuery` itself.
  LibraryQuery _intent(String text) =>
      LibraryQuery(text: text, sort: _sort, language: _languageFilter);

  /// Loads the head of the list for [query]: one page for a new intent, or
  /// the previously loaded depth for the same intent (D2-b). Records the
  /// intent and depth for the next comparison. The repository's `Either` is
  /// unwrapped into a value or a thrown `Failure`, which Riverpod's
  /// `build`/`AsyncValue.guard` turn into `AsyncError`.
  Future<LibraryWindow> _loadHead(LibraryQuery query) async {
    final sameIntent = query.sameIntentAs(_lastQuery);
    final depth = sameIntent
        ? math.max(_loadedDepth, libraryPageSize)
        : libraryPageSize;
    _lastQuery = query;
    _loadedDepth = depth;

    final repo = await ref.read(bookRepositoryProvider.future);
    final result = await repo.page(query, limit: depth);
    return result.fold(
      (failure) =>
          // ignore: only_throw_errors, Riverpod surfaces errors via throw
          throw failure,
      (BookPage page) {
        _loadedDepth = math.max(page.items.length, libraryPageSize);
        return LibraryWindow(
          books: List<Book>.unmodifiable(page.items),
          hasMore: page.hasMore,
        );
      },
    );
  }
}
