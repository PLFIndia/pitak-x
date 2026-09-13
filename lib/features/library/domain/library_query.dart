/// The library list's read intent, as one value (domain, pure Dart,
/// AGENTS.md §3.1).
///
/// Why this exists (N10-d part 2, astra-review.md N10): the Library screen's
/// controller always carried the same three things — the search-box text,
/// the persisted sort and the language chip — and the repository had two
/// methods (`query` for a blank box, `search` for a typed one) that took them
/// apart again. Pagination made a third split (whole list vs page) tempting.
/// Instead there is ONE read, `BookRepository.page`, that takes this value
/// plus a window; the "blank text → plain select, typed text → FTS" branch
/// lives in the repository next to the SQL that differs.
///
/// Value Object: immutable and normalised at construction. The controller
/// uses `sameIntentAs` to tell "the same list changed underneath me" (reload
/// to the depth the user had scrolled to) from "a different list" (start
/// again from the first page) — see `LibraryController`.
library;

import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Rows fetched per window of the library list. Roughly three phone screens
/// of rows or two tablet grids; the list quietly fetches the next window as
/// the user nears the end. One constant so it is tunable in one place.
const int libraryPageSize = 60;

/// Hard upper bound on a single page read, enforced by the repository. The
/// only path that asks for more than [libraryPageSize] is "reload what the
/// user had already scrolled to", which is bounded by real scrolling. A
/// caller asking for more than this gets this — it can never turn a page
/// read back into a whole-catalogue read.
const int maxLibraryPageSize = 500;

/// What the library list should show: which rows ([text], [language]) in
/// which order ([sort]).
final class LibraryQuery {
  /// Creates a normalised query. [text] and [language] are trimmed; a blank
  /// [text] becomes `''` (= "no search, list everything") and a blank
  /// [language] becomes `null` (= "all languages"), so two intents that mean
  /// the same thing are equal.
  LibraryQuery({required this.sort, String text = '', String? language})
    : text = text.trim(),
      language = _blankToNull(language);

  /// Search-box text, trimmed. Empty means "no search".
  final String text;

  /// Persisted list sort.
  final BookSort sort;

  /// Exact stored language to narrow to (N10-d D1-a), or null for all.
  final String? language;

  /// True when the list is a full-text search rather than a plain listing.
  bool get isSearch => text.isNotEmpty;

  /// True when [other] asks for the SAME list (same text, sort and facet) —
  /// a plain method rather than `==` so the value stays a simple final class
  /// without an `@immutable` dependency in the domain (N14 allowlist).
  bool sameIntentAs(LibraryQuery? other) =>
      other != null &&
      other.text == text &&
      other.sort == sort &&
      other.language == language;

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  String toString() =>
      'LibraryQuery(text: "$text", sort: $sort, language: $language)';
}
