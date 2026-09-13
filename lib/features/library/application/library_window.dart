/// The Library screen's list state (application layer, AGENTS.md §4/§7).
///
/// N10-d part 2 (astra-review.md N10): the screen no longer holds "the list"
/// — it holds the rows loaded SO FAR plus what it knows about the rest.
/// `LibraryController` owns one of these inside its `AsyncValue`; the page
/// renders `books`, shows a footer spinner while `isLoadingMore`, and asks
/// for the next window while `hasMore`.
///
/// Immutable: every change is a new instance via `copyWith`, so Riverpod's
/// equality-based rebuild logic sees each transition (§7).
library;

import 'package:pitaka/features/library/domain/entities/book.dart';

/// Rows loaded so far for the current intent, plus paging facts.
final class LibraryWindow {
  /// Creates a window.
  const LibraryWindow({
    required this.books,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  /// The rows shown, in list order — every page loaded so far, concatenated.
  final List<Book> books;

  /// Whether the store has more rows after [books] (from the last page read).
  final bool hasMore;

  /// True while the next page is being fetched. The rows stay visible; this
  /// only drives the footer indicator and de-duplicates `loadMore` calls.
  final bool isLoadingMore;

  /// Returns a copy with the given fields replaced.
  LibraryWindow copyWith({
    List<Book>? books,
    bool? hasMore,
    bool? isLoadingMore,
  }) => LibraryWindow(
    books: books ?? this.books,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );

  @override
  String toString() =>
      'LibraryWindow(${books.length} books, hasMore: $hasMore, '
      'isLoadingMore: $isLoadingMore)';
}
