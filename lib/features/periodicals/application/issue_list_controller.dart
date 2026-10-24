/// UI-facing issue list of ONE magazine title (periodicals application
/// layer, AGENTS.md §4; ADR 0013 U2).
///
/// A `@riverpod` AsyncNotifier FAMILY keyed by `periodicalUid`, driven by the
/// series detail page. Its state is the same [LibraryWindow] the Library
/// screen uses — the issues loaded so far, whether more exist, whether the
/// next page is in flight — because a series page is just the catalogue
/// narrowed to one `periodicalUid`: ONE paged read
/// (`CatalogueItemRepository.page`, N10-d) with `LibraryQuery.periodicalUid`
/// set. The repository orders such a list by the issue rules (newest issue
/// first, `IssueSorter`'s SQL twin), so the controller never sorts or
/// filters.
///
/// Freshness: every write path in the app already invalidates or refreshes
/// `libraryControllerProvider` (N03) — an issue added, edited, removed or
/// re-projected after a series edit fires it. Watching it here (value
/// ignored, same idiom as `catalogueItemById`) re-reads this list on that
/// one signal, with no new plumbing. The depth survives such a reload for
/// the same reason it does in `LibraryController` (D2-b): Riverpod keeps the
/// notifier instance across rebuilds of a live provider.
library;

import 'dart:math' as math;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'issue_list_controller.g.dart';

/// Loads and pages the issues of one series for the presentation layer.
@riverpod
class IssueListController extends _$IssueListController {
  /// How many rows the user has loaded (≥ one page once anything loaded). A
  /// reload re-reads this many rows so the list does not jump back to the
  /// top (D2-b).
  int _loadedDepth = libraryPageSize;

  /// N05: every new load (build, refresh) bumps this; a `loadMore` page
  /// publishes only if it still belongs to the newest revision, so a late
  /// page of an OLD read is dropped instead of being appended to the NEW one.
  int _revision = 0;

  /// The in-flight [loadMore], so concurrent calls collapse into one read.
  Future<void>? _loadingMore;

  @override
  FutureOr<LibraryWindow> build(String periodicalUid) {
    // The catalogue mutation signal (N03): value ignored, see the header.
    ref.watch(libraryControllerProvider);
    _supersede();
    return _loadHead();
  }

  /// Reloads the rows the user has already scrolled to (used after
  /// external mutations that do not go through the library signal).
  Future<void> refresh() async {
    final rev = _supersede();
    state = const AsyncLoading();
    final loaded = await AsyncValue.guard(_loadHead);
    if (rev == _revision) state = loaded;
  }

  /// Fetches the next page and appends it. No-op when nothing is loaded yet,
  /// when the store said there is no more, or while a previous call is still
  /// running (returns that call's future). A failed page keeps the rows
  /// already shown and clears the in-flight flag so the user can scroll
  /// again to retry (same contract as `LibraryController.loadMore`).
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
    final result = await repo.page(
      _intent,
      limit: libraryPageSize,
      offset: current.books.length,
    );
    // A newer load has taken over — it owns the state. Drop this page.
    if (rev != _revision) return;
    _loadingMore = null;
    if (state.hasError) return;
    final latest = state.valueOrNull ?? current;
    state = AsyncData(
      result.fold((_) => latest.copyWith(isLoadingMore: false), (page) {
        final books = List<CatalogueItem>.unmodifiable([
          ...latest.books,
          ...page.items,
        ]);
        _loadedDepth = books.length;
        return LibraryWindow(books: books, hasMore: page.hasMore);
      }),
    );
  }

  /// Starts a new load: bumps the N05 revision and forgets the pending
  /// `loadMore` so the next call can start a fresh one.
  int _supersede() {
    _revision++;
    _loadingMore = null;
    return _revision;
  }

  /// The read intent of this family instance. The sort is a fixed
  /// placeholder: the repository ignores `sort` when `periodicalUid` is set
  /// and applies the issue ordering instead (S10), but `LibraryQuery`
  /// requires one.
  LibraryQuery get _intent => LibraryQuery(
    sort: LibrarySort.recentlyAdded,
    periodicalUid: periodicalUid,
  );

  /// Loads the head of the list to the previously loaded depth (at least one
  /// page). The repository's `Either` is unwrapped into a value or a thrown
  /// `Failure`, which Riverpod's `build`/`AsyncValue.guard` turn into
  /// `AsyncError`.
  Future<LibraryWindow> _loadHead() async {
    final depth = math.max(_loadedDepth, libraryPageSize);
    final repo = await ref.read(catalogueItemRepositoryProvider.future);
    final result = await repo.page(_intent, limit: depth);
    return result.fold(
      (failure) =>
          // ignore: only_throw_errors, Riverpod surfaces errors via throw
          throw failure,
      (CatalogueItemPage page) {
        _loadedDepth = math.max(page.items.length, libraryPageSize);
        return LibraryWindow(
          books: List<CatalogueItem>.unmodifiable(page.items),
          hasMore: page.hasMore,
        );
      },
    );
  }
}
