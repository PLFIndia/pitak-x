/// World-facing publish payload (pure domain, AGENTS.md §3.1, #32).
///
/// Port of Kotlin `PublishExport` / `PublishBook`. This is the `books.json`
/// uploaded to GitHub Pages. SEPARATE from the re-importable export payload on
/// purpose: it carries ONLY viewer-facing catalog metadata plus a coarse
/// availability flag — never id, notes, location, source, addedDate (those are
/// stripped before a [PublishItem] is built; see `redactForPublish`).
library;

/// The full world-facing payload serialised to `books.json`.
final class PublishExport {
  /// Creates the payload.
  const PublishExport({
    required this.exportedAt,
    required this.books,
    this.periodicals = const [],
    this.schemaVersion = schemaVersionValue,
  });

  /// Payload schema version. Kept in lockstep with the viewer's
  /// `data.schemaVersion > N` guard; additive fields don't require a bump.
  static const int schemaVersionValue = 1;

  /// Declared schema version.
  final int schemaVersion;

  /// Epoch millis the payload was built.
  final int exportedAt;

  /// The world-facing book rows (books, magazine issues and others — the
  /// list kept its Kotlin-era name; the wire key stays `books`, ADR 0014).
  final List<PublishItem> books;

  /// The world-facing magazine titles the issues group under (ADR 0014 W3).
  /// Public fields only — see `redactPeriodicalForPublish`.
  final List<PublishPeriodical> periodicals;

  /// JSON map (camelCase keys mirror the Kotlin payload + viewer reads).
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt,
    'books': books.map((b) => b.toJson()).toList(),
    // Omitted when empty (the S18 Pitaka-JSON v4 rule): additive keys are
    // ignored by older viewers, and a library without magazines keeps the
    // payload it always had.
    if (periodicals.isNotEmpty)
      'periodicals': periodicals.map((p) => p.toJson()).toList(),
  };
}

/// One item in the world-facing payload. No id/notes/location/source/addedDate.
final class PublishItem {
  /// Creates a publish row. [kind] is required (ADR 0014 W3: every entry
  /// gains `kind`) so no mapping can silently default an issue to a book.
  const PublishItem({
    required this.title,
    required this.kind,
    this.issue,
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

  /// Title (may include subtitle). An issue's title is the composed,
  /// projected one ("<Series> — Vol 249 No 10 (Oct 2026)", ADR 0013 D3).
  final String title;

  /// Stable kind token (`book` / `magazine-issue` / `other`,
  /// `ItemKind.token`). Written for EVERY entry; absent on files published
  /// by older builds, which the viewer reads as `book`.
  final String kind;

  /// The issue part of a `magazine-issue` entry (public identity fields
  /// only); null for books and others.
  final PublishIssue? issue;

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
    'kind': kind,
    if (issue != null) 'issue': issue!.toJson(),
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

/// The issue part of a published magazine-issue entry (ADR 0013 D1, D4 —
/// the public identity fields; the item's private fields stay on the base
/// row and are stripped before a [PublishItem] is built).
final class PublishIssue {
  /// Creates the nested `issue{}` object.
  const PublishIssue({
    required this.periodicalUid,
    this.volume,
    this.issueNumber,
    this.issueDate,
    this.boundUntil,
    this.label,
  });

  /// `Periodical.periodicalUid` of the series — the viewer's grouping key
  /// into the payload's top-level `periodicals[]`.
  final String periodicalUid;

  /// Volume number, when the magazine numbers volumes.
  final int? volume;

  /// Issue number within the volume (or absolute), when known.
  final int? issueNumber;

  /// Cover date (epoch millis); for a bound volume, the FIRST issue's date.
  final int? issueDate;

  /// Bound volumes only: the LAST issue's date (epoch millis). Non-null is
  /// exactly what makes the viewer render the "Bound volume" badge.
  final int? boundUntil;

  /// Free-text label ("Dasara special"), optional.
  final String? label;

  /// JSON map; omits null fields.
  Map<String, dynamic> toJson() => {
    'periodicalUid': periodicalUid,
    if (volume != null) 'volume': volume,
    if (issueNumber != null) 'issueNumber': issueNumber,
    if (issueDate != null) 'issueDate': issueDate,
    if (boundUntil != null) 'boundUntil': boundUntil,
    if (label != null) 'label': label,
  };
}

/// One magazine title in the world-facing payload (ADR 0014 W3). PUBLIC
/// fields only — the subscription window, notes, location, source, added*
/// and the per-device id are stripped by `redactPeriodicalForPublish` and
/// never leave the device.
final class PublishPeriodical {
  /// Creates a publish row for a series.
  const PublishPeriodical({
    required this.periodicalUid,
    required this.title,
    this.titleTransliteration,
    this.issn,
    this.publisher,
    this.language,
    this.coverUrl,
    this.frequency,
    this.ageGroup,
  });

  /// Stable cross-device identity — the key an issue's
  /// [PublishIssue.periodicalUid] points at.
  final String periodicalUid;

  /// Series title.
  final String title;

  /// Roman-script title form, when recorded.
  final String? titleTransliteration;

  /// Canonical ISSN (`NNNN-NNNC`), when the title has one (D7).
  final String? issn;

  /// Publisher.
  final String? publisher;

  /// Language.
  final String? language;

  /// Cover URL (relative `covers/…` path or an allow-listed https URL).
  final String? coverUrl;

  /// Publication cadence token (`PeriodicalFrequency.token`), when known.
  final String? frequency;

  /// Reader age band token, or null.
  final String? ageGroup;

  /// JSON map; omits null fields so the payload stays compact.
  Map<String, dynamic> toJson() => {
    'periodicalUid': periodicalUid,
    'title': title,
    if (titleTransliteration != null)
      'titleTransliteration': titleTransliteration,
    if (issn != null) 'issn': issn,
    if (publisher != null) 'publisher': publisher,
    if (language != null) 'language': language,
    if (coverUrl != null) 'coverUrl': coverUrl,
    if (frequency != null) 'frequency': frequency,
    if (ageGroup != null) 'ageGroup': ageGroup,
  };
}
