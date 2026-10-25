/// Pure search / filter / sort / group engine for a published catalogue
/// (network domain, pure Dart; ADR 0015 V8/V9, viewer plan S3).
///
/// Everything here is a pure function of (catalogue, query): no HTTP, no
/// timers, no widgets, no mutable state. That is what makes the expensive pass
/// safe to run in a worker isolate and what makes the rules testable one
/// assertion at a time.
///
/// **Ordering.** The default is "Published order" — the payload's own order,
/// with `sourceIndex` as the final stable tie-break. There is deliberately NO
/// "Recently added" sort: `addedDate` is stripped before publishing, so the
/// payload cannot support it (V8). A sort never invents data.
///
/// **Grouping.** Filter and sort first, then group: a series header appears
/// where the sorted order first meets one of its issues, and only visible
/// issues appear in it. An issue whose series entry is missing (removed
/// locally, older payload) or whose uid is unusable stays a plain row — its
/// composed title already names the series.
library;

import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// The sort options the viewer offers.
enum PublishedSortOrder {
  /// Payload order (the published sequence); the default.
  publishedOrder,

  /// Language A→Z, blanks last.
  language,

  /// Reader age band, lowest first, unset last.
  ageGroup,
}

/// The kind filter chips.
enum PublishedKindFilter {
  /// Every readable row, including kinds this build does not understand.
  all,

  /// Books only.
  books,

  /// Magazine issues (including bound volumes) only.
  magazines,

  /// "Other" items only.
  others,
}

/// One immutable query intent.
final class PublishedCatalogueQuery {
  /// Creates a query. The defaults are the screen's opening state.
  const PublishedCatalogueQuery({
    this.search = '',
    this.kind = PublishedKindFilter.all,
    this.language,
    this.sort = PublishedSortOrder.publishedOrder,
  });

  /// Raw search text (matched case-insensitively against the five public
  /// fields the web viewer searches).
  final String search;

  /// Kind filter; [PublishedKindFilter.all] keeps unknown kinds too.
  final PublishedKindFilter kind;

  /// Exact language facet, or null for "all languages". Matched
  /// case-insensitively against the item's trimmed language.
  final String? language;

  /// Sort order.
  final PublishedSortOrder sort;

  /// Returns a copy with the given fields replaced. `language` needs an
  /// explicit [clearLanguage] flag because "all languages" is a real value
  /// (null), not "unchanged".
  PublishedCatalogueQuery copyWith({
    String? search,
    PublishedKindFilter? kind,
    String? language,
    PublishedSortOrder? sort,
    bool clearLanguage = false,
  }) => PublishedCatalogueQuery(
    search: search ?? this.search,
    kind: kind ?? this.kind,
    language: clearLanguage ? null : (language ?? this.language),
    sort: sort ?? this.sort,
  );
}

/// One row of the rendered list: either a plain item or a series group.
sealed class PublishedListEntry {
  const PublishedListEntry();
}

/// A plain item row.
final class PublishedItemEntry extends PublishedListEntry {
  /// Wraps [item].
  const PublishedItemEntry(this.item);

  /// The item to render.
  final PublishedCatalogueItem item;
}

/// A series header plus the issues visible inside it (newest first).
final class PublishedSeriesGroup extends PublishedListEntry {
  /// Creates a group; the issue list is stored unmodifiable.
  PublishedSeriesGroup({
    required this.series,
    required List<PublishedCatalogueItem> issues,
  }) : issues = List<PublishedCatalogueItem>.unmodifiable(issues);

  /// The public series entry shown in the header.
  final PublishedPeriodical series;

  /// Visible issues, ordered like the app's local `IssueSorter`.
  final List<PublishedCatalogueItem> issues;
}

/// What the page renders for one (catalogue, query) pair.
final class PublishedCatalogueView {
  /// Creates a view; [entries] is stored unmodifiable.
  PublishedCatalogueView({
    required List<PublishedListEntry> entries,
    required this.shownItems,
    required this.totalItems,
  }) : entries = List<PublishedListEntry>.unmodifiable(entries);

  /// Display rows in order (items and groups interleaved).
  final List<PublishedListEntry> entries;

  /// How many items match the query (issues inside groups included).
  final int shownItems;

  /// How many readable items the catalogue holds.
  final int totalItems;

  /// True when the query matches nothing.
  bool get hasNoMatches => shownItems == 0;
}

/// The pure query engine.
abstract final class PublishedQueryEngine {
  /// Applies [query] to [catalogue]. Never mutates the catalogue.
  static PublishedCatalogueView apply(
    PublishedCatalogue catalogue,
    PublishedCatalogueQuery query,
  ) {
    final needle = query.search.trim().toLowerCase();
    final language = query.language?.trim().toLowerCase();
    final filtered = <PublishedCatalogueItem>[];
    for (final item in catalogue.items) {
      if (!_matchesKind(item, query.kind)) continue;
      if (language != null && language.isNotEmpty) {
        final itemLanguage = item.language?.trim().toLowerCase() ?? '';
        if (itemLanguage != language) continue;
      }
      if (needle.isNotEmpty && !_matchesSearch(item, needle)) continue;
      filtered.add(item);
    }

    // Sort on a copy. Every comparator ends with `sourceIndex`, so equal keys
    // keep the published order and the result is fully deterministic.
    final sorted = List<PublishedCatalogueItem>.of(filtered)
      ..sort((a, b) => _compare(a, b, query.sort));
    return PublishedCatalogueView(
      entries: _group(sorted, catalogue.periodicals),
      shownItems: sorted.length,
      totalItems: catalogue.items.length,
    );
  }

  /// The language facet: distinct trimmed values, case-insensitive duplicates
  /// collapsed (the first spelling wins), sorted case-insensitively with a
  /// raw tie-break so the order never depends on the device locale.
  static List<String> languagesOf(PublishedCatalogue catalogue) {
    final seen = <String, String>{};
    for (final item in catalogue.items) {
      final label = item.language?.trim() ?? '';
      if (label.isEmpty) continue;
      seen.putIfAbsent(label.toLowerCase(), () => label);
    }
    final values = seen.values.toList()
      ..sort((a, b) {
        final byLower = a.toLowerCase().compareTo(b.toLowerCase());
        return byLower != 0 ? byLower : a.compareTo(b);
      });
    return List<String>.unmodifiable(values);
  }

  static bool _matchesKind(PublishedCatalogueItem item, PublishedKindFilter f) {
    return switch (f) {
      PublishedKindFilter.all => true,
      PublishedKindFilter.books => item.kind == PublishedItemKind.book,
      PublishedKindFilter.magazines =>
        item.kind == PublishedItemKind.magazineIssue,
      PublishedKindFilter.others => item.kind == PublishedItemKind.other,
    };
  }

  /// The five public fields the bundled web viewer searches. Excluded and
  /// unknown keys were never retained on the model, so a hostile `notes`,
  /// `location`, `source` or `addedBy` value cannot match here.
  static bool _matchesSearch(PublishedCatalogueItem item, String needle) {
    for (final field in <String?>[
      item.title,
      item.titleTransliteration,
      item.author,
      item.genre,
      item.isbn,
    ]) {
      if (field == null) continue;
      if (field.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  static int _compare(
    PublishedCatalogueItem a,
    PublishedCatalogueItem b,
    PublishedSortOrder order,
  ) => switch (order) {
    PublishedSortOrder.publishedOrder => a.sourceIndex.compareTo(b.sourceIndex),
    PublishedSortOrder.language => _byLanguage(a, b),
    PublishedSortOrder.ageGroup => _byAgeGroup(a, b),
  };

  static int _byLanguage(PublishedCatalogueItem a, PublishedCatalogueItem b) {
    final aLabel = a.language?.trim() ?? '';
    final bLabel = b.language?.trim() ?? '';
    final aBlank = aLabel.isEmpty;
    final bBlank = bLabel.isEmpty;
    // Blanks last, regardless of direction.
    if (aBlank != bBlank) return aBlank ? 1 : -1;
    final byLabel = aLabel.toLowerCase().compareTo(bLabel.toLowerCase());
    if (byLabel != 0) return byLabel;
    return a.sourceIndex.compareTo(b.sourceIndex);
  }

  static int _byAgeGroup(PublishedCatalogueItem a, PublishedCatalogueItem b) {
    final aRank = a.ageGroup?.sortRank;
    final bRank = b.ageGroup?.sortRank;
    if (aRank != bRank) {
      if (aRank == null) return 1;
      if (bRank == null) return -1;
      return aRank.compareTo(bRank);
    }
    return a.sourceIndex.compareTo(b.sourceIndex);
  }

  /// Groups the sorted items under their visible series entries.
  static List<PublishedListEntry> _group(
    List<PublishedCatalogueItem> sorted,
    List<PublishedPeriodical> periodicals,
  ) {
    if (periodicals.isEmpty) {
      return [for (final item in sorted) PublishedItemEntry(item)];
    }
    final byUid = <String, PublishedPeriodical>{
      for (final series in periodicals) series.periodicalUid: series,
    };
    final groups = <String, List<PublishedCatalogueItem>>{};
    // uid -> position of its header in `entries`, so a group can be replaced
    // in place after every issue is known (no shifting, no null placeholder
    // inside the public sealed union).
    final positions = <String, int>{};
    final entries = <PublishedListEntry>[];
    for (final item in sorted) {
      final uid = item.kind == PublishedItemKind.magazineIssue
          ? item.issue?.periodicalUid
          : null;
      final series = uid == null ? null : byUid[uid];
      if (uid == null || series == null) {
        // Orphan/partial issue or a non-issue: a plain row, in place.
        entries.add(PublishedItemEntry(item));
        continue;
      }
      final existing = groups[uid];
      if (existing == null) {
        groups[uid] = [item];
        positions[uid] = entries.length;
        // Temporary row; replaced with the group below, at the same index.
        entries.add(PublishedItemEntry(item));
      } else {
        existing.add(item);
      }
    }
    for (final group in positions.entries) {
      final issues = List<PublishedCatalogueItem>.of(groups[group.key]!)
        ..sort(_compareIssues);
      entries[group.value] = PublishedSeriesGroup(
        series: byUid[group.key]!,
        issues: issues,
      );
    }
    return entries;
  }

  /// The published twin of `IssueSorter.compare`: date desc, volume desc,
  /// issue number desc, missing values last, then `sourceIndex` ascending for
  /// a total stable order.
  static int _compareIssues(
    PublishedCatalogueItem a,
    PublishedCatalogueItem b,
  ) {
    final byDate = _descNullsLast(a.issue?.issueDate, b.issue?.issueDate);
    if (byDate != 0) return byDate;
    final byVolume = _descNullsLast(a.issue?.volume, b.issue?.volume);
    if (byVolume != 0) return byVolume;
    final byNumber = _descNullsLast(a.issue?.issueNumber, b.issue?.issueNumber);
    if (byNumber != 0) return byNumber;
    return a.sourceIndex.compareTo(b.sourceIndex);
  }

  /// Descending on present values; a null sorts after any value; two nulls
  /// tie (the next key decides). Identical to `IssueSorter._descNullsLast`.
  static int _descNullsLast(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}
