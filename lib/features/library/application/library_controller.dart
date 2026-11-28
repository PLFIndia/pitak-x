/// UI-facing library controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the Library screen drives. Its state is a
/// [LibraryWindow]: the rows loaded so far for one intent (search text +
/// persisted sort + language chip + kind chip), whether more exist and
/// whether the next page is in flight. Queries are debounced (120ms) to
/// avoid hammering SQLite on every
/// keystroke. The repository returns `Either<Failure, _>`; a left on a
/// load of the list's head becomes `AsyncError(Failure)` so the UI can
/// render a safe message (raw exception text is never surfaced).
///
/// ## Windows, not the catalogue (review finding N10-d part 2, "lists load
/// the whole catalogue")
///
/// The controller reads ONE page (`libraryPageSize` rows) on build and
/// appends the next page on `loadMore` as the user nears the end of the
/// list. The repository produces the final order, filter and window inside
/// SQLite (part 1 + 2), so the controller never sorts, filters or slices.
///
/// ## One listener of the "catalogue changed" signal (review findings
/// P4-M2 and P3-M4, ADR 0031)
///
/// Until November 2026 this list's state WAS the app's "catalogue changed"
/// signal: every write path reloaded or invalidated this provider, and
/// everything else watched it. Two things followed. Scrolling and typing,
/// which change this state, made the whole app read again; and a write
/// could only tell the others by making the list say "loading", which the
/// screen drew as a spinner in place of the rows, so the place was lost.
///
/// Now the write paths tell `catalogueChangesProvider`, and `build` WATCHES
/// it like everybody else. Every load of the list's head is therefore a
/// run of `build`, and Riverpod itself keeps the old rows in the state
/// while it runs. Nothing here sets "loading" by hand.
///
/// Two kinds of load, decided by comparing the new [LibraryQuery] with the
/// one the rows on the screen answer (user decision S30, D2-b; D152, D153):
///
///  - **The same list, read again** (a change was said, or Retry): the
///    rows the user had scrolled to are read again, in pieces of at most
///    `maxLibraryPageSize`, so the list does not jump back to the top. The
///    window keeps its `listSerial`.
///  - **Another list** (sort changed, chip tapped, new search text): one
///    page, and the next `listSerial`, which makes the screen start it at
///    the top.
///
/// What the rows on the screen belong to is remembered in `_shown`, which
/// survives a rebuild because Riverpod keeps the SAME notifier instance
/// across rebuilds of a live provider (only a full dispose, no listeners,
/// recreates it).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_controller.g.dart';

/// Debounce window before a typed query hits SQLite.
const _searchDebounce = Duration(milliseconds: 120);

/// Thrown inside a load that a newer load has overtaken, to end it. It
/// never reaches the screen: Riverpod throws away whatever an overtaken
/// `build` ends with, an error as much as a value.
final class _Overtaken implements Exception {
  const _Overtaken();
}

/// Loads and pages the library book list for the presentation layer.
@riverpod
class LibraryController extends _$LibraryController {
  Timer? _debounce;
  String _query = '';

  /// The window that is on the screen: the last one a load of the head or a
  /// `loadMore` published. Null before the first load has ended. It says
  /// which question the rows answer, how deep they go and which
  /// `listSerial` they carry; written ONLY where a window is published, so
  /// a load that fails or is overtaken leaves it alone.
  LibraryWindow? _shown;

  /// N05: every run of [build] bumps this, and a read publishes its result
  /// ONLY if it still belongs to the newest revision. A query already
  /// running in SQLite cannot be cancelled, and its late answer must
  /// neither overwrite the answer to a newer one nor be followed by more
  /// reads. [loadMore] runs under the revision it started with, so a late
  /// page of an OLD list is dropped instead of being appended to the NEW
  /// one. Only [build] bumps it: "overtaken" here then always means that
  /// Riverpod, too, has started a newer `build`.
  int _revision = 0;

  /// The in-flight [loadMore], so concurrent calls (a fast fling fires many
  /// scroll notifications) collapse into one read.
  Future<void>? _loadingMore;

  @override
  FutureOr<LibraryWindow> build() async {
    // Cancel any in-flight debounce when the provider is disposed.
    ref.onDispose(() => _debounce?.cancel());
    // This run reads with the text as it is now, so a pause that is still
    // running after a typed letter has nothing left to do.
    _debounce?.cancel();
    // A rebuild (a change said, sort/language change, typed text, Retry)
    // supersedes any read still in flight, including a pending loadMore.
    final revision = _supersede();
    // WATCH the app's "catalogue changed" signal (ADR 0031): a write
    // anywhere in the app rebuilds this provider, which reads the same list
    // again. The value is a counter and is not used.
    ref.watch(catalogueChangesProvider);
    // WATCH the persisted sort (narrowed with select, §8): changing it in
    // Settings rebuilds this provider and re-sorts the list immediately.
    // A ref.read here would freeze the sort until an unrelated refresh.
    final sort = ref.watch(
      settingsControllerProvider.select(
        (s) => s.maybeWhen(
          data: (settings) => settings.librarySort,
          orElse: () => LibrarySort.recentlyAdded,
        ),
      ),
    );
    // WATCH the language facet the same way: it is real provider state (see
    // library_filter_controller.dart), so a chip tap rebuilds this list AND
    // the chips from one source of truth.
    final language = ref.watch(libraryLanguageFilterProvider);
    // The kind chips (ADR 0013 U1) are a second facet with the same
    // contract: provider state, watched here, so a tap is a new intent.
    final kind = ref.watch(libraryKindFilterProvider);
    return _loadHead(
      revision,
      LibraryQuery(text: _query, sort: sort, language: language, kind: kind),
    );
  }

  /// The current query text (so the UI can render the field without owning it).
  String get query => _query;

  /// Updates the query and, after a short pause without another letter,
  /// reads the list for it. An empty query restores the full list.
  ///
  /// The read is a run of [build] (`ref.invalidateSelf`), like every other
  /// load of the head: the rows on the screen stay until the new ones are
  /// there, and [build]'s revision makes sure an older, slower search can
  /// never land last (N05).
  void onQueryChanged(String query) {
    _query = query;
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, ref.invalidateSelf);
  }

  /// Reads the list on the screen again, to the depth it has (the error
  /// screen's Retry). Nobody waits for it: the state says when it is done.
  void refresh() => ref.invalidateSelf();

  /// Fetches the next page and appends it. No-op when nothing is loaded yet,
  /// when the store said there is no more, while the head is being read
  /// again, or while a previous call is still running (returns that call's
  /// future). A failed page keeps the rows already shown and clears the
  /// in-flight flag so the user can scroll again to retry — a list the user
  /// is looking at is never blanked into an error for a page they have not
  /// seen yet.
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
    final repo = await ref.read(catalogueItemRepositoryProvider.future);
    // The next page of the list ON THE SCREEN (`current.query`), which is
    // not always the text in the search box: after a typed letter the old
    // rows stay until the new ones are there.
    final result = await repo.page(
      current.query,
      limit: libraryPageSize,
      offset: current.books.length,
    );
    // Riverpod rebuilds lazily: when a change was said while this page was
    // being read, `build` has not run again yet unless somebody has asked
    // for the state since. Asking for it here lets that rebuild start (it
    // bumps the revision), so the comparison below sees it.
    final now = state;
    // N05 extension: a newer load has taken over — [_supersede] already
    // cleared `_loadingMore` and the new load owns the state. Drop this page.
    if (rev != _revision) return;
    _loadingMore = null;
    // A write failed while this page was in flight (`remove`/`restoreRemoved`
    // set AsyncError without a new revision): keep that error visible rather
    // than paint data over it (§5 fail closed).
    if (now.hasError) return;
    final latest = now.valueOrNull ?? current;
    state = AsyncData(
      result.fold((_) => latest.copyWith(isLoadingMore: false), (page) {
        final grown = latest.copyWith(
          books: List<CatalogueItem>.unmodifiable([
            ...latest.books,
            ...page.items,
          ]),
          hasMore: page.hasMore,
          isLoadingMore: false,
        );
        _shown = grown;
        return grown;
      }),
    );
  }

  /// Starts a new load of the head: bumps the N05 revision so every read
  /// still in flight (a piece of an older head OR a `loadMore` page) is
  /// dropped when it lands, and forgets the pending `loadMore` so the next
  /// call can start a fresh one. Returns the new revision for the load to
  /// compare against.
  int _supersede() {
    _revision++;
    _loadingMore = null;
    return _revision;
  }

  /// Soft-deletes book [id] (stays visible-but-inert), then says "changed".
  /// It does not wait for the list to be read again (D154): this list and
  /// everything else that shows the item hear the signal and catch up.
  ///
  /// Fail closed (§5): a repository Left becomes `AsyncError(Failure)` — a
  /// failed write must never tell the app that something changed.
  Future<void> remove(int id) => _write(
    (repo) => repo.markRemoved(id, DateTime.now().millisecondsSinceEpoch),
  );

  /// Clears the soft-delete flag on book [id], then says "changed". Fails
  /// closed like [remove].
  Future<void> restoreRemoved(int id) =>
      _write((repo) => repo.restoreRemoved(id));

  /// Runs one write and turns its answer into what the app is told.
  ///
  /// Everything this needs from `ref` is read BEFORE the first wait. This
  /// provider watches the signal, so after a wait it may itself be waiting
  /// to be rebuilt (another write said "changed" meanwhile), and in that
  /// state Riverpod refuses `ref.read` in debug builds. Callers reach this
  /// through `ref.read(libraryControllerProvider.notifier)`, which brings
  /// the provider up to date first.
  Future<void> _write(
    Future<Either<Failure, Unit>> Function(CatalogueItemRepository repo) write,
  ) async {
    final changes = ref.read(catalogueChangesProvider.notifier);
    final repository = ref.read(catalogueItemRepositoryProvider.future);
    final result = await write(await repository);
    result.fold(
      (failure) => state = AsyncError(failure, StackTrace.current),
      (_) => changes.changed(),
    );
  }

  /// Loads the head of the list for [query] under [revision]: one page for
  /// another list, or the depth of the rows on the screen for the same list
  /// (D2-b), read in pieces of at most `maxLibraryPageSize` (D153).
  ///
  /// The cap on a single read keeps its purpose (a page read can never turn
  /// into a whole-catalogue read); a deep list simply takes several reads.
  /// After every piece the load looks whether a newer one has begun and, if
  /// so, reads no further: a burst of changes (covers downloaded one by
  /// one) cannot pile up whole deep reloads. Every write says "changed",
  /// which starts a newer load; so a load that reaches its end has read all
  /// its pieces with no write in between that the app knows of.
  ///
  /// The repository's `Either` is unwrapped into a value or a thrown
  /// `Failure`, which Riverpod's `build` turns into `AsyncError`.
  Future<LibraryWindow> _loadHead(int revision, LibraryQuery query) async {
    final shown = _shown;
    final sameList = shown != null && query.sameIntentAs(shown.query);
    final depth = sameList
        ? math.max(shown.books.length, libraryPageSize)
        : libraryPageSize;

    final repo = await ref.read(catalogueItemRepositoryProvider.future);
    if (revision != _revision) throw const _Overtaken();
    final rows = <CatalogueItem>[];
    var hasMore = true;
    while (hasMore && rows.length < depth) {
      final result = await repo.page(
        query,
        limit: math.min(maxLibraryPageSize, depth - rows.length),
        offset: rows.length,
      );
      if (revision != _revision) throw const _Overtaken();
      final page = result.fold(
        (failure) =>
            // ignore: only_throw_errors, Riverpod surfaces errors via throw
            throw failure,
        (page) => page,
      );
      rows.addAll(page.items);
      hasMore = page.hasMore;
      // A store that says "more" and hands over nothing would keep this
      // loop asking for ever. Stop with what there is.
      if (page.items.isEmpty) break;
    }

    // Still the newest load, and it has its rows: from here on THIS is the
    // window on the screen.
    final window = LibraryWindow(
      books: List<CatalogueItem>.unmodifiable(rows),
      hasMore: hasMore,
      query: query,
      listSerial: sameList ? shown.listSerial : (shown?.listSerial ?? 0) + 1,
    );
    _shown = window;
    return window;
  }
}
