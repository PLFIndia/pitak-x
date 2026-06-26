/// One row of a title-based search (pure domain, AGENTS.md §3.1).
///
/// Mirror of Kotlin `TitleSearchResult`: the fallback path when the user can't
/// find a book by ISBN scan and searches by title instead. `sourceKey` is the
/// upstream provider's stable id (Open Library `key` / Google Books `id`),
/// retained only for a potential future "details" fetch.
library;

/// A single title-search hit. Immutable.
final class TitleSearchResult {
  /// Creates a search result. [sourceKey] and [title] are required.
  const TitleSearchResult({
    required this.sourceKey,
    required this.title,
    this.author,
    this.publishedYear,
    this.isbn,
    this.coverUrl,
  });

  /// Upstream provider's stable identifier.
  final String sourceKey;

  /// Result title.
  final String title;

  /// First listed author, when present.
  final String? author;

  /// First publication year, when present.
  final int? publishedYear;

  /// An ISBN-10/13 from the result, when present.
  final String? isbn;

  /// Cover image URL (remote `https://`), when present.
  final String? coverUrl;
}
