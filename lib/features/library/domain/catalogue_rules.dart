/// Field-level validation rules for the catalogue entities (`CatalogueItem` and
/// `WishlistBook` — not imported here to keep this leaf dependency-free) —
/// the single source of truth every ingress must pass through (review finding
/// M15: imports coerced instead of validating, persisting values that later
/// crashed normal screens).
///
/// Why this exists (beginner note): before M15, only the add/edit forms
/// checked anything (and only "title not blank"). The JSON/CSV importers and
/// the backup restore reader built entities straight from untrusted file
/// bytes, so a crafted file could plant values that CRASH normal screens
/// later: an `addedDate` above `maxDateMillis` throws `RangeError` in
/// `DateTime.fromMillisecondsSinceEpoch` (detail page, date picker, CSV/PDF
/// export); a wishlist `priority` of 7 trips the dropdown's "exactly one
/// item" assertion; a `priceEstimate` of Infinity makes `jsonEncode` throw on
/// the next export. Coercion is not validation: these rules REJECT invalid
/// values at the boundary instead of silently keeping them.
///
/// Cover references are the one exception: they are NORMALISED (dropped to
/// null), never a rejection, so a pre-M15 database row carrying a
/// now-disallowed URL stays editable (see the `CatalogueItem.validate` doc).
///
/// The numeric bounds mirror the Rust vault core (`rust/src/api.rs`
/// `MAX_DATE_MILLIS`, `validate_date`) so both trusted cores agree on what a
/// valid date is. Pure Dart, no Flutter/IO (AGENTS.md §3.1); cross-feature
/// domain imports are allowed by the architecture gate
/// (`test/architecture/domain_purity_test.dart`).
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Shared validation primitives + limits for catalogue entities.
abstract final class CatalogueRules {
  /// Largest epoch-millis value Dart's `DateTime` can represent. Identical to
  /// the Rust core's `MAX_DATE_MILLIS` (`rust/src/api.rs`) — keep them in
  /// lockstep. `DateTime.fromMillisecondsSinceEpoch(max + 1)` throws.
  static const int maxDateMillis = 8640000000000000;

  /// Max characters kept for any single text field. Single source of truth:
  /// `ImportLimits.defaults.maxFieldChars` references this constant.
  static const int maxFieldChars = 8000;

  /// Smallest accepted publication year. Display-only today, but a 20-digit
  /// "year" is still junk data; 1..9999 matches `DateTime` years.
  static const int minYear = 1;

  /// Largest accepted publication year (see [minYear]).
  static const int maxYear = 9999;

  /// A required epoch-millis date: `0` is the "unset" sentinel (detail page
  /// renders nothing, import-merge treats it as "keep existing"); otherwise
  /// 1..[maxDateMillis].
  static bool isValidDateMillis(int value) =>
      value >= 0 && value <= maxDateMillis;

  /// An optional epoch-millis date: null (absent) or a valid date.
  static bool isValidOptionalDateMillis(int? value) =>
      value == null || isValidDateMillis(value);

  /// A date range in order: true when either end is absent or [until] is on
  /// or after [from] (same day counts). Used for a bound volume's
  /// `issueDate..boundUntil` and a subscription window (ADR 0013 D4, D5).
  static bool isValidDateOrder(int? from, int? until) =>
      from == null || until == null || until >= from;

  /// A publication year: null (unknown) or 1..9999.
  static bool isValidYear(int? year) =>
      year == null || (year >= minYear && year <= maxYear);

  /// A countable quantity (copies, pages): null (unknown) or at least 1.
  /// Zero/negative copies break availability math (`active >= copyCount`
  /// publishes a zero-copy book as "out" with no loans).
  static bool isValidCount(int? count) => count == null || count >= 1;

  /// A price: null (unknown) or finite and non-negative. NaN/Infinity cannot
  /// round-trip through JSON (`jsonEncode` throws) and are meaningless here.
  static bool isValidPrice(double? price) =>
      price == null || (price.isFinite && price >= 0);

  /// A bounded text field: null (absent) or within [maxFieldChars].
  static bool isValidFieldText(String? value) =>
      value == null || value.length <= maxFieldChars;

  /// The comparison key for a free-text `sourceDetail` (donor / seller
  /// name): trimmed and lower-cased, or null when blank.
  /// `CatalogueItem.sourceDetail` is typed by hand, so "Ram Sharma" and
  /// "ram sharma " must count as the
  /// SAME person wherever details are listed or matched — the repository's
  /// distinct-detail facet and the export filter both compare by this key,
  /// so a value picked from the one always matches in the other. Dart's
  /// `toLowerCase` is Unicode-aware (SQLite's `lower()` is ASCII-only, which
  /// is why this is done in Dart).
  static String? sourceDetailKey(String? value) {
    final key = value?.trim().toLowerCase();
    return (key == null || key.isEmpty) ? null : key;
  }

  /// Converts epoch millis to a `DateTime`, or null when the value is not a
  /// representable date. Display/export code uses this so a row persisted
  /// BEFORE M15 (or by a hostile file on an older build) renders without a
  /// date instead of throwing `RangeError` — ingress rejects such rows now,
  /// but rendering must never crash on old data.
  static DateTime? dateFromMillisOrNull(int millis) {
    if (!isValidDateMillis(millis) || millis == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// A cover reference: null/blank (none), a safe LOCAL ref (`covers/<leaf>`
  /// or legacy `file://…/<leaf>` — traversal/smuggling rejected by
  /// [CoverPaths.leafOf]), or a REMOTE https URL on the publish allow-list
  /// ([CoverUrlAllowList.sanitize]). Anything else (e.g. `http://`, unknown
  /// hosts) is rejected so a hostile file cannot plant tracking URLs that
  /// would survive re-export.
  static bool isValidCoverRef(String? coverUrl) {
    final s = coverUrl?.trim() ?? '';
    if (s.isEmpty) return true;
    if (CoverPaths.isLocal(s)) return CoverPaths.leafOf(s) != null;
    return CoverUrlAllowList.sanitize(s) != null;
  }
}

/// One field that failed validation: which [field] and a plain-English
/// [problem] safe to show the user (no raw exception text, no values echoed
/// back beyond the field name).
final class FieldError {
  /// Creates a field error.
  const FieldError(this.field, this.problem);

  /// The entity field name (e.g. `copyCount`).
  final String field;

  /// Plain-English description of the violation (e.g. 'must be at least 1').
  final String problem;

  /// Beginner-friendly sentence for the form snackbar, e.g. 'Copies must be
  /// at least 1.' Falls back to the raw field name for unmapped fields.
  String get userMessage {
    final label = switch (field) {
      'title' => 'A title',
      'addedDate' => 'The date added',
      'removedAt' => 'The removal date',
      'purchasedDate' => 'The purchase date',
      'copyCount' => 'Copies',
      'pageCount' => 'The page count',
      'publishedYear' => 'The publication year',
      'priority' => 'The priority',
      'priceEstimate' => 'The price estimate',
      'coverUrl' => 'The cover link',
      // Periodicals (ADR 0013 D2, D5, D7).
      'issn' => 'The ISSN',
      'frequency' => 'The frequency',
      'subscriptionStart' => 'The subscription start date',
      'subscriptionEnd' => 'The subscription end date',
      // Magazine issues (`IssueOf.validate`, ADR 0013 D1, D4).
      'issue.periodicalUid' => 'The magazine title',
      'issue.volume' => 'The volume number',
      'issue.issueNumber' => 'An issue number',
      'issue.issueDate' => 'The issue date',
      'issue.boundUntil' => 'The last issue date',
      'issue.label' => 'The issue label',
      _ => field,
    };
    return '$label $problem.';
  }

  @override
  String toString() => '$field: $problem';
}
