/// World-facing publish payload (pure domain, AGENTS.md §3.1, #32).
///
/// Port of Kotlin `PublishExport` / `PublishBook`. This is the `books.json`
/// uploaded to GitHub Pages. SEPARATE from the re-importable export payload on
/// purpose: it carries ONLY viewer-facing catalog metadata plus a coarse
/// availability flag — never id, notes, location, source, addedDate (those are
/// stripped before a [PublishBook] is built; see `redactForPublish`).
library;

/// The full world-facing payload serialised to `books.json`.
final class PublishExport {
  /// Creates the payload.
  const PublishExport({
    required this.exportedAt,
    required this.books,
    this.schemaVersion = schemaVersionValue,
  });

  /// Payload schema version. Kept in lockstep with the viewer's
  /// `data.schemaVersion > N` guard; additive fields don't require a bump.
  static const int schemaVersionValue = 1;

  /// Declared schema version.
  final int schemaVersion;

  /// Epoch millis the payload was built.
  final int exportedAt;

  /// The world-facing book rows.
  final List<PublishBook> books;

  /// JSON map (camelCase keys mirror the Kotlin payload + viewer reads).
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt,
    'books': books.map((b) => b.toJson()).toList(),
  };
}

/// One book in the world-facing payload. No id/notes/location/source/addedDate.
final class PublishBook {
  /// Creates a publish row.
  const PublishBook({
    required this.title,
    this.titleTransliteration,
    this.author,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.genre,
    this.language,
    this.coverUrl,
    this.ageGroup,
    this.availability,
  });

  /// Coarse availability sentinel: at least one copy free.
  static const String available = 'available';

  /// Coarse availability sentinel: all copies lent out.
  static const String out = 'out';

  /// Title (may include subtitle).
  final String title;

  /// Title transliteration.
  final String? titleTransliteration;

  /// Author(s).
  final String? author;

  /// ISBN.
  final String? isbn;

  /// Publisher.
  final String? publisher;

  /// Publication year.
  final int? publishedYear;

  /// Genre/subjects.
  final String? genre;

  /// Language.
  final String? language;

  /// Cover URL (relative `covers/…` path or an allow-listed https URL).
  final String? coverUrl;

  /// Reader age band token (`above-3`…`advanced`), or null. Public info.
  final String? ageGroup;

  /// Coarse availability ([available]/[out]) or null when not computed (vault
  /// locked at publish). NEVER an exact count.
  final String? availability;

  /// JSON map; omits null fields so the payload stays compact and the
  /// viewer reads optional keys defensively.
  Map<String, dynamic> toJson() => {
    'title': title,
    if (titleTransliteration != null)
      'titleTransliteration': titleTransliteration,
    if (author != null) 'author': author,
    if (isbn != null) 'isbn': isbn,
    if (publisher != null) 'publisher': publisher,
    if (publishedYear != null) 'publishedYear': publishedYear,
    if (genre != null) 'genre': genre,
    if (language != null) 'language': language,
    if (coverUrl != null) 'coverUrl': coverUrl,
    if (ageGroup != null) 'ageGroup': ageGroup,
    if (availability != null) 'availability': availability,
  };
}
