/// Which library books a CSV/PDF export includes, by provenance (domain,
/// AGENTS.md §3.1 — pure Dart, no Flutter/IO).
///
/// A librarian wants "the books Ram Sharma donated" as a PDF to hand back to
/// the donor, or "everything we purchased" for the accounts. This Value
/// Object names that selection once so the use case (filtering), the file
/// name and the PDF subtitle all agree on what was asked for.
///
/// Value Object (beginner note): a small immutable type whose identity IS
/// its values — two filters with the same type + detail mean the same thing
/// (compare with [ExportSourceFilter.sameAs]). Invalid states are
/// unrepresentable: a detail can only exist together with a type (a donor
/// name means nothing without "donated"), because the only constructor that
/// accepts a detail also requires the type.
library;

import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Narrows an export to one [BookSourceType], optionally to one
/// [sourceDetail] within it.
final class ExportSourceFilter {
  /// Every book, whatever its source (the default).
  const ExportSourceFilter.all() : sourceType = null, sourceDetail = null;

  /// Books whose `sourceType` is [type]; when [detail] is non-blank, only
  /// those whose `sourceDetail` matches it too (compared by
  /// [CatalogueRules.sourceDetailKey]: trimmed, case-insensitive).
  ///
  /// [detail] is normalised here — trimmed, blank → null — so callers never
  /// have to remember to.
  ExportSourceFilter.byType(BookSourceType type, {String? detail})
    : sourceType = type,
      sourceDetail = _trimToNull(detail);

  /// The provenance category to keep, or null for "all".
  final BookSourceType? sourceType;

  /// The free-text detail to keep (trimmed, never blank), or null for "any
  /// detail". Always null when [sourceType] is null.
  final String? sourceDetail;

  /// True when this filter narrows the list at all.
  bool get isActive => sourceType != null;

  /// Whether [book] passes the filter. A book with no source recorded never
  /// matches an active filter (it is not "donated" just because we do not
  /// know where it came from).
  bool matches(Book book) {
    final type = sourceType;
    if (type == null) return true;
    if (book.sourceType != type) return false;
    final wanted = CatalogueRules.sourceDetailKey(sourceDetail);
    if (wanted == null) return true;
    return CatalogueRules.sourceDetailKey(book.sourceDetail) == wanted;
  }

  /// The subset of [books] that [matches], in the same order.
  List<Book> apply(List<Book> books) =>
      isActive ? books.where(matches).toList(growable: false) : books;

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// True when [other] asks for the SAME subset (type and detail) — a plain
  /// method rather than `==` so the value stays a simple final class without
  /// an `@immutable` dependency in the domain (same convention as
  /// `LibraryQuery.sameIntentAs`).
  bool sameAs(ExportSourceFilter other) =>
      other.sourceType == sourceType && other.sourceDetail == sourceDetail;

  @override
  String toString() => isActive
      ? 'ExportSourceFilter(${sourceType!.name}'
            '${sourceDetail == null ? '' : ', $sourceDetail'})'
      : 'ExportSourceFilter.all';
}
