/// One window of the library list (domain, pure Dart, AGENTS.md §3.1).
///
/// N10-d part 2 (astra-review.md N10, "lists load the whole catalogue"): the
/// repository no longer hands the controller every row; it hands it a page
/// and says whether another one exists. `hasMore` is decided by the store
/// (it asks SQLite for one row more than the page and drops it), so the
/// caller never needs a separate COUNT(*) — which over the FTS join would be
/// a second full walk of the index.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';

/// A contiguous slice of the ordered, filtered library list.
final class BookPage {
  /// Creates a page. [items] is taken as-is (the repository already returns
  /// an unmodifiable list); [hasMore] is true when at least one more row
  /// follows the last item in the same order.
  const BookPage({required this.items, required this.hasMore});

  /// An empty terminal page.
  static const BookPage empty = BookPage(items: [], hasMore: false);

  /// The rows in list order.
  final List<Book> items;

  /// Whether a further page exists after [items].
  final bool hasMore;

  @override
  String toString() => 'BookPage(${items.length} items, hasMore: $hasMore)';
}
