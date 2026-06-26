/// Metadata returned by an ISBN lookup (pure domain, AGENTS.md §3.1).
///
/// Mirror of Kotlin `BookMetadata`: the subset of `Book` fields that public
/// ISBN APIs reliably populate. Every field except `isbn` is optional — Open
/// Library and Google Books return wildly inconsistent records, so we accept
/// what's present and ignore what isn't (graceful degradation). Pure Dart: no
/// Flutter/IO/JSON imports.
library;

/// Book metadata from an ISBN lookup provider. Immutable.
final class BookMetadata {
  /// Creates metadata. Only [isbn] is required.
  const BookMetadata({
    required this.isbn,
    this.title,
    this.author,
    this.publisher,
    this.publishedYear,
    this.pageCount,
    this.coverUrl,
    this.genre,
    this.language,
  });

  /// The looked-up ISBN (normalised form).
  final String isbn;

  /// Title (may already include subtitle, "Title: Subtitle").
  final String? title;

  /// Author(s), comma-joined when several.
  final String? author;

  /// Publisher name.
  final String? publisher;

  /// Publication year, parsed from a free-form date when needed.
  final int? publishedYear;

  /// Page count.
  final int? pageCount;

  /// Cover image URL (remote `https://`).
  final String? coverUrl;

  /// Genre/subjects, comma-joined (capped upstream).
  final String? genre;

  /// Language code/name when the provider exposes it.
  final String? language;
}
