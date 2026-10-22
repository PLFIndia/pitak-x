/// A magazine title — the series every issue belongs to (periodicals
/// domain, pure Dart, AGENTS.md §3.1; ADR 0013 D2).
///
/// The periodical is the single writer of everything an issue inherits
/// (title, publisher, language, age group): `IssueProjection` copies those
/// onto each issue's base row, so every existing consumer keeps reading
/// plain `CatalogueItem` columns. Identity across devices is
/// `periodicalUid` (a UUID minted at first persist, like `itemUid`).
///
/// Immutable; `copyWith` for edits. Like `CatalogueItem`, the plain
/// constructor is the trusted fast path (DB mapper, `copyWith` on a
/// persisted row) and the static `validate` gate is what every INGRESS —
/// form, import, merge, restore — must pass a row through before it is
/// persisted (AGENTS §3.3 accepted deviation, ADR 0004; enforced by
/// `test/architecture/catalogue_item_validation_gate_test.dart`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// One magazine title. `id == emptyId` means "not yet persisted".
class Periodical {
  /// Creates a periodical. Only [title] is required.
  const Periodical({
    required this.title,
    this.id = emptyId,
    this.periodicalUid,
    this.titleTransliteration,
    this.issn,
    this.publisher,
    this.language,
    this.coverUrl,
    this.frequency,
    this.subscriptionStart,
    this.subscriptionEnd,
    this.notes,
    this.location,
    this.sourceType,
    this.sourceDetail,
    this.ageGroup,
    this.addedDate = 0,
    this.removed = false,
    this.removedAt,
    this.addedBy,
  });

  /// Sentinel meaning "not yet persisted".
  static const int emptyId = 0;

  /// Per-device autoincrement id. Meaningless across installs (use
  /// [periodicalUid]).
  final int id;

  /// Stable globally-unique identity (UUID), minted once at first persist
  /// and carried through export/import unchanged — the key every issue's
  /// `IssueOf.periodicalUid` points at. Null only means "not yet persisted".
  final String? periodicalUid;

  /// Required title, native script.
  final String title;

  /// Optional Roman-script form for search; projected onto issues.
  final String? titleTransliteration;

  /// Canonical ISSN (`NNNN-NNNC`), unique among non-null values (D7).
  final String? issn;

  /// Publisher; projected onto issues.
  final String? publisher;

  /// Language; projected onto issues.
  final String? language;

  /// Series cover reference (same forms as `CatalogueItem.coverUrl`); the
  /// fallback cover of every issue that has none of its own (ADR 0014 W4).
  final String? coverUrl;

  /// Publication cadence, when known.
  final PeriodicalFrequency? frequency;

  /// Epoch millis the subscription started, when tracked (private).
  final int? subscriptionStart;

  /// Epoch millis the subscription ends, when tracked (private). Null means
  /// the subscription is not tracked — `SubscriptionStatus` derives
  /// everything else from this date (D5).
  final int? subscriptionEnd;

  /// Free-form notes (private; stripped at publish).
  final String? notes;

  /// Free-form shelf location (private; stripped at publish).
  final String? location;

  /// How the subscription/title was acquired (private).
  final ItemSourceType? sourceType;

  /// Free-form provenance specifics (private).
  final String? sourceDetail;

  /// Reader age band (public); projected onto issues (D3: no per-issue
  /// override).
  final AgeGroup? ageGroup;

  /// Epoch millis at insert; never edited.
  final int addedDate;

  /// Soft-delete flag; a removed title stays visible but actionless. Its
  /// issues are untouched (D8).
  final bool removed;

  /// Epoch millis when removed; null when active.
  final int? removedAt;

  /// Self-asserted maintainer handle that first catalogued this title.
  final String? addedBy;

  /// True when the subscription window is tracked (D5).
  bool get isSubscriptionTracked => subscriptionEnd != null;

  /// Validates [periodical] against the shared `CatalogueRules` and the
  /// periodical's own rules, returning a normalised copy (title trimmed,
  /// ISSN canonical, unsafe cover dropped) or every field error found.
  ///
  /// Same contract as `CatalogueItem.validate`: the cover reference is
  /// normalised, never a rejection (a pre-existing row must stay editable);
  /// everything else is rejected at the boundary, not coerced.
  static Either<List<FieldError>, Periodical> validate(Periodical periodical) {
    final errors = <FieldError>[];

    final title = periodical.title.trim();
    if (title.isEmpty) {
      errors.add(const FieldError('title', 'is required'));
    }

    final textFields = <String, String?>{
      'title': title,
      'periodicalUid': periodical.periodicalUid,
      'titleTransliteration': periodical.titleTransliteration,
      'publisher': periodical.publisher,
      'language': periodical.language,
      'notes': periodical.notes,
      'location': periodical.location,
      'sourceDetail': periodical.sourceDetail,
      'addedBy': periodical.addedBy,
    };
    for (final entry in textFields.entries) {
      if (!CatalogueRules.isValidFieldText(entry.value)) {
        errors.add(
          FieldError(
            entry.key,
            'must be at most ${CatalogueRules.maxFieldChars} characters',
          ),
        );
      }
    }

    // ISSN: blank means "none"; anything else must be a structurally valid
    // ISSN and is stored in its canonical dashed form so the UNIQUE index
    // compares like with like ("09776058" and "0977-6058" are one title).
    final rawIssn = periodical.issn?.trim() ?? '';
    final String? canonicalIssn;
    if (rawIssn.isEmpty) {
      canonicalIssn = null;
    } else {
      canonicalIssn = Issn.normalize(rawIssn);
      if (canonicalIssn == null) {
        errors.add(const FieldError('issn', 'is not a valid ISSN'));
      }
    }

    if (!CatalogueRules.isValidDateMillis(periodical.addedDate)) {
      errors.add(const FieldError('addedDate', 'is not a representable date'));
    }
    if (!CatalogueRules.isValidOptionalDateMillis(periodical.removedAt)) {
      errors.add(const FieldError('removedAt', 'is not a representable date'));
    }
    final startOk = CatalogueRules.isValidOptionalDateMillis(
      periodical.subscriptionStart,
    );
    if (!startOk) {
      errors.add(
        const FieldError('subscriptionStart', 'is not a representable date'),
      );
    }
    final endOk = CatalogueRules.isValidOptionalDateMillis(
      periodical.subscriptionEnd,
    );
    if (!endOk) {
      errors.add(
        const FieldError('subscriptionEnd', 'is not a representable date'),
      );
    }
    if (startOk &&
        endOk &&
        !CatalogueRules.isValidDateOrder(
          periodical.subscriptionStart,
          periodical.subscriptionEnd,
        )) {
      errors.add(
        const FieldError(
          'subscriptionEnd',
          'must not be before the subscription start',
        ),
      );
    }

    final rawCover = periodical.coverUrl?.trim() ?? '';
    final safeCover = CatalogueRules.isValidCoverRef(rawCover)
        ? (rawCover.isEmpty ? null : rawCover)
        : null;

    if (errors.isNotEmpty) return left(errors);
    if (title == periodical.title &&
        safeCover == periodical.coverUrl &&
        canonicalIssn == periodical.issn) {
      return right(periodical);
    }
    return right(
      Periodical(
        id: periodical.id,
        periodicalUid: periodical.periodicalUid,
        title: title,
        titleTransliteration: periodical.titleTransliteration,
        issn: canonicalIssn,
        publisher: periodical.publisher,
        language: periodical.language,
        coverUrl: safeCover,
        frequency: periodical.frequency,
        subscriptionStart: periodical.subscriptionStart,
        subscriptionEnd: periodical.subscriptionEnd,
        notes: periodical.notes,
        location: periodical.location,
        sourceType: periodical.sourceType,
        sourceDetail: periodical.sourceDetail,
        ageGroup: periodical.ageGroup,
        addedDate: periodical.addedDate,
        removed: periodical.removed,
        removedAt: periodical.removedAt,
        addedBy: periodical.addedBy,
      ),
    );
  }

  /// Returns a copy with the given fields replaced (null keeps the current
  /// value, like every `copyWith` in this codebase).
  Periodical copyWith({
    int? id,
    String? periodicalUid,
    String? title,
    String? titleTransliteration,
    String? issn,
    String? publisher,
    String? language,
    String? coverUrl,
    PeriodicalFrequency? frequency,
    int? subscriptionStart,
    int? subscriptionEnd,
    String? notes,
    String? location,
    ItemSourceType? sourceType,
    String? sourceDetail,
    AgeGroup? ageGroup,
    int? addedDate,
    bool? removed,
    int? removedAt,
    String? addedBy,
  }) {
    return Periodical(
      id: id ?? this.id,
      periodicalUid: periodicalUid ?? this.periodicalUid,
      title: title ?? this.title,
      titleTransliteration: titleTransliteration ?? this.titleTransliteration,
      issn: issn ?? this.issn,
      publisher: publisher ?? this.publisher,
      language: language ?? this.language,
      coverUrl: coverUrl ?? this.coverUrl,
      frequency: frequency ?? this.frequency,
      subscriptionStart: subscriptionStart ?? this.subscriptionStart,
      subscriptionEnd: subscriptionEnd ?? this.subscriptionEnd,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      sourceType: sourceType ?? this.sourceType,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      ageGroup: ageGroup ?? this.ageGroup,
      addedDate: addedDate ?? this.addedDate,
      removed: removed ?? this.removed,
      removedAt: removedAt ?? this.removedAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  /// True when [other] has the same catalogue content (every field except
  /// the per-device [id]) — a plain method rather than `==` so the entity
  /// stays a simple class without an `@immutable` dependency in the domain
  /// (same convention as `NetworkLibrary.sameAs`).
  bool sameAs(Periodical other) =>
      periodicalUid == other.periodicalUid &&
      title == other.title &&
      titleTransliteration == other.titleTransliteration &&
      issn == other.issn &&
      publisher == other.publisher &&
      language == other.language &&
      coverUrl == other.coverUrl &&
      frequency == other.frequency &&
      subscriptionStart == other.subscriptionStart &&
      subscriptionEnd == other.subscriptionEnd &&
      notes == other.notes &&
      location == other.location &&
      sourceType == other.sourceType &&
      sourceDetail == other.sourceDetail &&
      ageGroup == other.ageGroup &&
      addedDate == other.addedDate &&
      removed == other.removed &&
      removedAt == other.removedAt &&
      addedBy == other.addedBy;
}
