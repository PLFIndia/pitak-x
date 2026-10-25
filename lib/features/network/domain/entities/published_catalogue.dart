/// Read-only, published-view models for one library's `books.json`
/// (network domain, pure Dart; ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// Why these are NOT the local entities (beginner note): a local
/// `CatalogueItem` has a database id, editing behaviour, lending semantics and
/// private fields that `books.json` simply does not carry. Reusing it would
/// invite an accidental import or an edit of somebody else's catalogue.
/// These classes describe exactly what a *reader* may show, and nothing else:
/// no id, no notes, no location, no added date, no copy count.
///
/// `sourceIndex` is the item's position in the published `books` array. It is
/// session-local, never published and never persisted; it exists only so
/// sorting and grouping have a stable tie-break and widgets a stable key.
///
/// A newer declared schema is NOT an error: the payload still decodes, the
/// fields this build understands are shown, and `hasNewerSchema` drives a
/// persistent warning (ADR 0015 decision 4).
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// The schema version this build reads. `books.json` versions above this one
/// are read forward-tolerantly, with a visible warning.
const int publishedCatalogueSchemaVersion = 1;

/// What one published row claims to be (ADR 0014 W3).
///
/// Deliberately separate from `ItemKind`: an unrecognised token is
/// [unknown] — a plain, badge-less item — not an import rejection, and not a
/// silent [book]. `ItemKind.fromToken` is NOT used here because its trimming,
/// case folding and enum-name aliases are broader than the published contract.
enum PublishedItemKind {
  /// No `kind` key at all (payloads written before kinds existed) or `book`.
  book,

  /// `magazine-issue`: one issue or a bound volume.
  magazineIssue,

  /// `other`: a DVD, board game, map… described only by common fields.
  other,

  /// A token this build does not understand: show common fields only, no
  /// kind badge, and count it for the limited-detail warning.
  unknown,
}

/// Coarse availability sentinel from publish time (never a live loan query,
/// never a count).
enum PublishedAvailability {
  /// At least one copy was free when the catalogue was published.
  available,

  /// All copies were lent out when the catalogue was published.
  out,
}

/// The public issue identity of a published magazine issue or bound volume.
///
/// Display data only — no local id and no lending behaviour. A published file
/// is a snapshot: this object is never written back anywhere.
final class PublishedIssueDetails {
  /// Creates issue details. All fields are already validated/normalized.
  const PublishedIssueDetails({
    this.periodicalUid,
    this.volume,
    this.issueNumber,
    this.issueDate,
    this.boundUntil,
    this.label,
  });

  /// Canonical series uid, or null when the published value was unusable.
  final String? periodicalUid;

  /// Volume number when the magazine numbers volumes (≥ 1).
  final int? volume;

  /// Issue number (≥ 1) when known.
  final int? issueNumber;

  /// Cover calendar day at 00:00 UTC, normalized with the app's stored-value
  /// rule; an instant in the payload, a calendar day for display.
  final int? issueDate;

  /// Bound volumes only: the last issue's day, normalized like [issueDate].
  /// Only ever set when both dates are valid and in order.
  final int? boundUntil;

  /// Free-text label ("Dasara special") when present and within the field cap.
  final String? label;

  /// True when this row is a bound volume (a date range), false otherwise.
  bool get isBound => boundUntil != null;
}

/// One readable row of a published catalogue.
final class PublishedCatalogueItem {
  /// Creates an item. Every field has already passed the reader's rules.
  const PublishedCatalogueItem({
    required this.sourceIndex,
    required this.title,
    required this.kind,
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
    this.issue,
  });

  /// Position in the published `books` array (session-local, stable).
  final int sourceIndex;

  /// Required display title (never blank, never over the field cap).
  final String title;

  /// What the payload claims this row is.
  final PublishedItemKind kind;

  /// Roman-script title form when present.
  final String? titleTransliteration;

  /// Author(s) when present (books and issues only).
  final String? author;

  /// ISBN when present (books and issues only).
  final String? isbn;

  /// Publisher when present (books and issues only).
  final String? publisher;

  /// Publication year, 1..9999, when present (books and issues only).
  final int? publishedYear;

  /// Genre/subjects when present (books and issues only).
  final String? genre;

  /// Language when present (any kind).
  final String? language;

  /// Sanitized cover reference (`covers/<leaf>` or an allow-listed https URL).
  /// Null when the published value was blank or unsafe — never requests.
  final String? coverUrl;

  /// Reader age band when present and recognised (any kind).
  final AgeGroup? ageGroup;

  /// Coarse publish-time availability (books and issues only).
  final PublishedAvailability? availability;

  /// Public issue identity (magazine issues only).
  final PublishedIssueDetails? issue;

  /// True when this row should carry no kind badge.
  bool get isUnknownKind => kind == PublishedItemKind.unknown;
}

/// One public magazine series from the payload's additive `periodicals[]`.
///
/// Carries only what grouping/detail needs; private periodical fields
/// (subscription window, notes, location, source) are never published and are
/// not represented here at all.
final class PublishedPeriodical {
  /// Creates a public series entry.
  const PublishedPeriodical({
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

  /// Canonical cross-device series identity (the grouping key).
  final String periodicalUid;

  /// Required series title.
  final String title;

  /// Roman-script title form when present.
  final String? titleTransliteration;

  /// Canonical ISSN when present.
  final String? issn;

  /// Publisher when present.
  final String? publisher;

  /// Language when present.
  final String? language;

  /// Sanitized cover reference, or null.
  final String? coverUrl;

  /// Publication cadence when the token is recognised.
  final PeriodicalFrequency? frequency;

  /// Reader age band when present and recognised.
  final AgeGroup? ageGroup;
}

/// Structured, enum-like counts of everything the reader had to drop.
///
/// Counts and booleans only — never a remote string. The UI turns these into
/// one safe sentence ("Some entries couldn't be displayed"); the raw values
/// that failed validation are never kept, searched or shown.
final class PublishedCatalogueWarnings {
  /// Creates a warning tally (all zero by default).
  const PublishedCatalogueWarnings({
    this.droppedItems = 0,
    this.droppedPeriodicals = 0,
    this.invalidOptionalFields = 0,
    this.unknownKindItems = 0,
    this.duplicateSeriesUids = 0,
    this.itemsTruncated = false,
    this.periodicalsTruncated = false,
    this.invalidExportedAt = false,
  });

  /// Item rows dropped because a required field was missing or unusable.
  final int droppedItems;

  /// Periodical rows dropped because a required field was unusable.
  final int droppedPeriodicals;

  /// Optional fields present but dropped (wrong type, over cap, bad date…).
  final int invalidOptionalFields;

  /// Items with a `kind` token this build does not understand.
  final int unknownKindItems;

  /// Duplicate canonical series uids (last valid entry wins; counted).
  final int duplicateSeriesUids;

  /// The `books` array was longer than the per-collection row cap.
  final bool itemsTruncated;

  /// The `periodicals` array was longer than the per-collection row cap.
  final bool periodicalsTruncated;

  /// `exportedAt` was present but not a usable epoch-millis value.
  final bool invalidExportedAt;

  /// True when at least one ROW or FIELD was refused, so the UI must say so.
  ///
  /// [invalidExportedAt] is deliberately excluded: a bad publish timestamp
  /// means the date is simply not shown, not that entries are missing, and the
  /// banner's wording ("Some entries couldn't be displayed") must stay honest.
  bool get hasPartialRead =>
      droppedItems > 0 ||
      droppedPeriodicals > 0 ||
      invalidOptionalFields > 0 ||
      itemsTruncated ||
      periodicalsTruncated;

  /// True when at least one row's kind was not understood.
  bool get hasUnknownKinds => unknownKindItems > 0;
}

/// One decoded published catalogue: the complete, read-only payload.
final class PublishedCatalogue {
  /// Creates a decoded catalogue. The lists are stored unmodifiable so no
  /// caller can mutate what another screen is rendering.
  PublishedCatalogue({
    required this.declaredSchemaVersion,
    required List<PublishedCatalogueItem> items,
    required List<PublishedPeriodical> periodicals,
    this.exportedAt,
    this.warnings = const PublishedCatalogueWarnings(),
  }) : items = List<PublishedCatalogueItem>.unmodifiable(items),
       periodicals = List<PublishedPeriodical>.unmodifiable(periodicals);

  /// The schema version the payload declares (may be newer than this build).
  final int declaredSchemaVersion;

  /// Publish time as epoch millis, or null when absent/unusable. An INSTANT,
  /// unlike an issue's calendar day.
  final int? exportedAt;

  /// Readable item rows, in payload order.
  final List<PublishedCatalogueItem> items;

  /// Readable public series entries, in payload order.
  final List<PublishedPeriodical> periodicals;

  /// What the reader had to drop.
  final PublishedCatalogueWarnings warnings;

  /// True when the payload was written by a newer Pitak: known fields are
  /// shown, unknown ones were ignored, and the UI keeps a visible warning.
  bool get hasNewerSchema =>
      declaredSchemaVersion > publishedCatalogueSchemaVersion;

  /// True when the payload had rows but the reader could display none.
  bool get hasNoReadableItems =>
      items.isEmpty && (warnings.droppedItems > 0 || warnings.itemsTruncated);
}

/// The published age-group tokens this build recognises (ADR 0015 V9).
///
/// Exact tokens only — no trimming, no case folding, no enum-name aliases:
///  - the five current tokens (`above-3` … `advanced`);
///  - the four LEGACY tokens the bundled HTML viewer still accepts
///    (`AGE_0_5`, `AGE_6_10`, `AGE_11_16`, `ADVANCE`), mapped to the closest
///    band exactly like the viewer's `AGE_ORDER`/`AGE_LABEL` tables.
///
/// Anything else is absent (the item simply has no age badge). This is
/// deliberately narrower than `AgeGroup.fromToken`, which also accepts enum
/// names and lower-cased variants — that tolerance belongs to local import,
/// not to a hostile public payload being displayed.
AgeGroup? parsePublishedAgeGroup(Object? raw) {
  if (raw is! String) return null;
  return switch (raw) {
    'above-3' => AgeGroup.above3,
    'above-6' => AgeGroup.above6,
    'above-10' => AgeGroup.above10,
    'above-15' => AgeGroup.above15,
    'advanced' => AgeGroup.advanced,
    // Legacy pre-"above N" tokens (the bundled viewer maps the same way).
    'AGE_0_5' => AgeGroup.above3,
    'AGE_6_10' => AgeGroup.above6,
    'AGE_11_16' => AgeGroup.above10,
    'ADVANCE' => AgeGroup.advanced,
    _ => null,
  };
}
