/// Dart-side source of truth for the library's ordering semantics
/// (domain, pure Dart, AGENTS.md §3.1).
///
/// Why this exists (N05, astra-review.md): the search path used to return
/// the repository's hardcoded newest-first rows even when the user had picked
/// Language or Age-group sort. The SQL-backed `query()` orders in SQL; the
/// FTS search path cannot reuse that SQL, so it sorts its matches here with
/// the SAME rules:
///
///  - recentlyAdded → newest `addedDate` first;
///  - languageAsc   → blank/null languages LAST, then language A→Z
///                    (binary code-unit order, matching SQLite's default
///                    collation), ties newest-first;
///  - ageGroupAsc   → [AgeGroup.sortRank] order (NOT token-alphabetical),
///                    nulls last, ties newest-first.
///
/// All sorts are stable: equal keys keep their incoming order.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Sorts book lists by the app's persisted [BookSort] contract.
abstract final class BookSorter {
  /// Returns a NEW list of [books] ordered by [sort]. Never mutates [books].
  static List<Book> sort(List<Book> books, BookSort sort) {
    final indexed = books.asMap().entries.toList()
      ..sort((a, b) {
        final byKey = switch (sort) {
          BookSort.recentlyAdded => 0, // only the tie-break below applies
          BookSort.languageAsc => _byLanguage(a.value, b.value),
          BookSort.ageGroupAsc => _byAgeRank(a.value, b.value),
        };
        if (byKey != 0) return byKey;
        // Shared tie-break: newest-added first (mirrors the SQL ORDER BY).
        final byAdded = b.value.addedDate.compareTo(a.value.addedDate);
        if (byAdded != 0) return byAdded;
        // Stable: keep the incoming order for exact ties.
        return a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Blank/null languages sort LAST, then code-unit A→Z (SQLite BINARY
  /// collation parity with the SQL path).
  static int _byLanguage(Book a, Book b) {
    final la = (a.language ?? '').trim();
    final lb = (b.language ?? '').trim();
    final aBlank = la.isEmpty;
    final bBlank = lb.isEmpty;
    if (aBlank != bBlank) return aBlank ? 1 : -1; // blanks last
    return la.compareTo(lb);
  }

  /// Band order is [AgeGroup.sortRank]; books with no band sort last.
  static int _byAgeRank(Book a, Book b) {
    final ra = a.ageGroup?.sortRank ?? 1 << 30;
    final rb = b.ageGroup?.sortRank ?? 1 << 30;
    return ra.compareTo(rb);
  }
}
