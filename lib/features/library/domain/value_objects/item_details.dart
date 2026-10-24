/// Kind-specific data of a catalogue item (ADR 0013 F5) — domain, pure Dart.
///
/// Why a sealed union (beginner note): `CatalogueItem.details` is either
/// `null` (a book), an [IssueOf] (a magazine issue) or an [OtherItemOf] (an
/// "other" item). Because the class is `sealed`, a `switch (item.details)`
/// must handle every member or it does not compile — so adding a kind can
/// never leave a screen, exporter or mapper silently ignoring it. The kind
/// is *derived* from the member ([ItemDetails.kind]), so a row can never
/// claim one kind while carrying another kind's fields.
library;

import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/periodical_identity.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

/// The kind-specific part of a catalogue item. Members are immutable value
/// objects that validate themselves; `CatalogueItem.validate` appends their
/// errors to its own.
sealed class ItemDetails {
  const ItemDetails();

  /// The kind this member stands for (derived, never stored separately).
  ItemKind get kind;

  /// Field-level rules of this member, as `issue.<field>` style errors so a
  /// form can point at the right input. Empty when valid.
  List<FieldError> validate();

  /// True when [other] carries the same kind and the same field values — a
  /// plain method rather than `==` so the members stay simple final classes
  /// without an `@immutable` dependency in the domain (N14 allowlist).
  bool sameAs(ItemDetails? other);
}

/// A magazine issue — or a bound volume of issues — of one periodical
/// (ADR 0013 D1, D4).
///
/// Two shapes share this class:
/// - a **single issue**: [issueNumber] and/or [issueDate] identify it
///   (`volume` optional), [boundUntil] is null;
/// - a **bound volume**: [issueDate] is the first issue and [boundUntil] the
///   last issue bound together — one physical item, one `copyCount`, one
///   loan. Numbers are optional and the range may span volume numbers.
///
/// Value semantics: compare two details with [sameAs] (the domain keeps
/// plain final classes without an `@immutable` dependency, same convention
/// as `LibraryQuery.sameIntentAs`).
final class IssueOf extends ItemDetails {
  /// Creates issue details. [periodicalUid] links the row to its periodical
  /// (a soft link: the uid is the cross-device identity, ADR 0013 D2).
  const IssueOf({
    required this.periodicalUid,
    this.volume,
    this.issueNumber,
    this.issueDate,
    this.boundUntil,
    this.label,
  });

  /// `Periodical.periodicalUid` of the series this issue belongs to.
  final String periodicalUid;

  /// Volume number, when the magazine numbers volumes (≥ 1).
  final int? volume;

  /// Issue number within the volume (or absolute), when known (≥ 1).
  final int? issueNumber;

  /// Cover calendar day at 00:00 UTC (epoch millis); for a bound volume, the
  /// FIRST day in the range. Not a local-midnight instant.
  final int? issueDate;

  /// For a bound volume only: the LAST calendar day in the range at 00:00
  /// UTC (epoch millis, ≥ [issueDate]). Null for a single issue.
  final int? boundUntil;

  /// Free-text label ("Dasara special", "Annual number"), optional.
  final String? label;

  /// True when this row is a bound volume (a date range), false for a
  /// single issue.
  bool get isBound => boundUntil != null;

  @override
  ItemKind get kind => ItemKind.magazineIssue;

  /// Returns the canonical ingress/persistence form of these details.
  ///
  /// Valid date-only values become UTC-midnight [CalendarDate]s and the soft
  /// link is trimmed. Invalid integers are left for [validate] to report, not
  /// coerced or thrown away. This method is shared by the entity gate, D6
  /// lookups, and Drift companions so they can never disagree on a key.
  IssueOf normalized() {
    final uid = canonicalPeriodicalUid(periodicalUid);
    final normalizedDate = CatalogueRules.isValidOptionalDateMillis(issueDate)
        ? CalendarDate.normalizeOptionalStoredMillis(issueDate)
        : issueDate;
    final normalizedUntil = CatalogueRules.isValidOptionalDateMillis(boundUntil)
        ? CalendarDate.normalizeOptionalStoredMillis(boundUntil)
        : boundUntil;
    if (uid == periodicalUid &&
        normalizedDate == issueDate &&
        normalizedUntil == boundUntil) {
      return this;
    }
    return copyWith(
      periodicalUid: uid,
      issueDate: normalizedDate,
      boundUntil: normalizedUntil,
    );
  }

  @override
  List<FieldError> validate() {
    final errors = <FieldError>[];
    if (periodicalUid.trim().isEmpty) {
      errors.add(const FieldError('issue.periodicalUid', 'is required'));
    } else if (!CatalogueRules.isValidFieldText(periodicalUid)) {
      errors.add(
        const FieldError(
          'issue.periodicalUid',
          'must be at most ${CatalogueRules.maxFieldChars} characters',
        ),
      );
    }
    if (!CatalogueRules.isValidCount(volume)) {
      errors.add(const FieldError('issue.volume', 'must be at least 1'));
    }
    if (!CatalogueRules.isValidCount(issueNumber)) {
      errors.add(const FieldError('issue.issueNumber', 'must be at least 1'));
    }
    final dateOk = CatalogueRules.isValidOptionalDateMillis(issueDate);
    if (!dateOk) {
      errors.add(
        const FieldError('issue.issueDate', 'is not a representable date'),
      );
    }
    final untilOk = CatalogueRules.isValidOptionalDateMillis(boundUntil);
    if (!untilOk) {
      errors.add(
        const FieldError('issue.boundUntil', 'is not a representable date'),
      );
    }
    if (isBound) {
      // A bound volume is "issues from X to Y": both dates are required and
      // the range must not run backwards. Only checked when both dates are
      // representable, so one bad input yields one error, not two.
      if (issueDate == null) {
        errors.add(
          const FieldError('issue.issueDate', 'is required for a bound volume'),
        );
      } else if (dateOk &&
          untilOk &&
          !CatalogueRules.isValidDateOrder(issueDate, boundUntil)) {
        errors.add(
          const FieldError(
            'issue.boundUntil',
            'must not be before the first issue date',
          ),
        );
      }
    } else if (issueNumber == null && issueDate == null) {
      // A single issue needs something to be identified by (ADR 0013 D6):
      // a number, a date, or both.
      errors.add(
        const FieldError('issue.issueNumber', 'or an issue date is required'),
      );
    }
    if (!CatalogueRules.isValidFieldText(label)) {
      errors.add(
        const FieldError(
          'issue.label',
          'must be at most ${CatalogueRules.maxFieldChars} characters',
        ),
      );
    }
    return errors;
  }

  /// Returns a copy with the given fields replaced (null keeps the current
  /// value, like every `copyWith` in this codebase).
  IssueOf copyWith({
    String? periodicalUid,
    int? volume,
    int? issueNumber,
    int? issueDate,
    int? boundUntil,
    String? label,
  }) {
    return IssueOf(
      periodicalUid: periodicalUid ?? this.periodicalUid,
      volume: volume ?? this.volume,
      issueNumber: issueNumber ?? this.issueNumber,
      issueDate: issueDate ?? this.issueDate,
      boundUntil: boundUntil ?? this.boundUntil,
      label: label ?? this.label,
    );
  }

  @override
  bool sameAs(ItemDetails? other) =>
      other is IssueOf &&
      other.periodicalUid == periodicalUid &&
      other.volume == volume &&
      other.issueNumber == issueNumber &&
      other.issueDate == issueDate &&
      other.boundUntil == boundUntil &&
      other.label == label;

  @override
  String toString() =>
      'IssueOf($periodicalUid, vol: $volume, no: $issueNumber, '
      'date: $issueDate, until: $boundUntil, label: $label)';
}

/// An "other" item (ADR 0013 O1): a kind with no fields of its own. The
/// marker exists so the union is exhaustive and so a future field has a
/// home without touching the base row.
final class OtherItemOf extends ItemDetails {
  /// Creates the marker. Every instance is equal to every other.
  const OtherItemOf();

  @override
  ItemKind get kind => ItemKind.other;

  @override
  List<FieldError> validate() => const [];

  @override
  bool sameAs(ItemDetails? other) => other is OtherItemOf;

  @override
  String toString() => 'OtherItemOf()';
}
