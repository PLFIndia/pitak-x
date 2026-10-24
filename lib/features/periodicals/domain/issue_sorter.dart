/// Ordering contract for a periodical's issue list (periodicals domain,
/// pure Dart; ADR 0013 U2) — the oracle the repository's SQL is tested
/// against, in the same role `CatalogueItemSorter` plays for the Library.
///
/// Newest issue first: `issueDate` desc, then `volume` desc, then
/// `issueNumber` desc, then `id` desc. A missing key sorts AFTER every
/// present one at that level (an undated issue goes below dated ones), so
/// the SQL twin must order `… DESC NULLS LAST`. The sort is total — ties on
/// every key cannot exist because `id` is unique — so paging in SQL is
/// stable.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Sorts issue lists newest-first.
abstract final class IssueSorter {
  /// Returns a NEW list of [issues] in the contract order. Never mutates
  /// [issues]. Rows that are not issues (no `IssueOf`) are treated as
  /// having no date, volume or number: they sort last, by id desc.
  static List<CatalogueItem> sort(List<CatalogueItem> issues) =>
      List<CatalogueItem>.of(issues)..sort(compare);

  /// The contract as a comparator (negative when [a] sorts before [b]).
  static int compare(CatalogueItem a, CatalogueItem b) {
    final byDate = _descNullsLast(a.issue?.issueDate, b.issue?.issueDate);
    if (byDate != 0) return byDate;
    final byVolume = _descNullsLast(a.issue?.volume, b.issue?.volume);
    if (byVolume != 0) return byVolume;
    final byNumber = _descNullsLast(a.issue?.issueNumber, b.issue?.issueNumber);
    if (byNumber != 0) return byNumber;
    return b.id.compareTo(a.id);
  }

  /// Descending on present values; a null sorts after any value; two nulls
  /// tie (the next key decides).
  static int _descNullsLast(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}
