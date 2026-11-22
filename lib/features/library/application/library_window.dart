/// The Library screen's list state (application layer, AGENTS.md §4/§7).
///
/// Review finding N10-d part 2 ("lists load the whole catalogue"): the screen
/// no longer holds "the list"
/// — it holds the rows loaded SO FAR plus what it knows about the rest.
/// `LibraryController` owns one of these inside its `AsyncValue`; the page
/// renders `books`, shows a footer spinner while `isLoadingMore`, and asks
/// for the next window while `hasMore`.
///
/// Immutable: every change is a new instance via `copyWith`, so Riverpod's
/// equality-based rebuild logic sees each transition (§7).
///
/// Review finding P4-M2 (ADR 0031): while a list is read again its OLD rows
/// stay on the screen. So the window also says which question its rows
/// answer (`query`) and whether they are another list than the one before
/// (`listSerial`); the screen must not work that out from what the user has
/// typed or tapped since, because the rows it shows may be older than that.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';

/// Rows loaded so far for one intent, plus paging facts.
final class LibraryWindow {
  /// Creates a window.
  const LibraryWindow({
    required this.books,
    required this.hasMore,
    required this.query,
    this.isLoadingMore = false,
    this.listSerial = 0,
  });

  /// The rows shown, in list order — every page loaded so far, concatenated.
  final List<CatalogueItem> books;

  /// The question [books] answer: the search text, sort and chips they were
  /// read for. An empty list explains itself from this ("nothing matches
  /// these filters" or "your library is empty"), not from the search box,
  /// which may already hold the next question.
  final LibraryQuery query;

  /// Goes up by one each time [books] belong to ANOTHER list (other search
  /// text, chip or sort), and stays the same while the same list is read
  /// again or grows by a page. The Library screen uses it as the key of its
  /// scroll view: the same number keeps the place, a new number starts at
  /// the top. A screen that only ever shows one list leaves it at 0.
  final int listSerial;

  /// Whether the store has more rows after [books] (from the last page read).
  final bool hasMore;

  /// True while the next page is being fetched. The rows stay visible; this
  /// only drives the footer indicator and de-duplicates `loadMore` calls.
  final bool isLoadingMore;

  /// Returns a copy with the given fields replaced. [query] and [listSerial]
  /// are kept: a copy is always the SAME list, with more rows or with its
  /// footer switched.
  LibraryWindow copyWith({
    List<CatalogueItem>? books,
    bool? hasMore,
    bool? isLoadingMore,
  }) => LibraryWindow(
    books: books ?? this.books,
    hasMore: hasMore ?? this.hasMore,
    query: query,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    listSerial: listSerial,
  );

  @override
  String toString() =>
      'LibraryWindow(${books.length} books, hasMore: $hasMore, '
      'isLoadingMore: $isLoadingMore, list $listSerial)';
}
