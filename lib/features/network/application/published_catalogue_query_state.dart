/// The viewer's query intent (network application layer; viewer plan S3).
///
/// Two search values on purpose:
///  - `search` is what the text field shows — updated on every keystroke so
///    typing feels immediate;
///  - `activeSearch` is the DEBOUNCED term the engine actually runs, updated
///    120 ms after typing stops (the same window `LibraryController` uses).
///
/// The derived view watches the ACTIVE intent only (via a record `select`), so
/// a burst of keystrokes can never start a burst of isolate passes. The class
/// is immutable but deliberately has no `==`: the repo's domain/application
/// state classes use `sameAs`-style helpers instead, and Riverpod's `select`
/// on a record supplies the structural comparison the rebuild scope needs.
library;

import 'package:pitaka/features/network/domain/published_catalogue_query.dart';

/// One immutable snapshot of the viewer's controls.
final class PublishedCatalogueQueryState {
  /// Creates the opening state: no search, all kinds, all languages,
  /// published order.
  const PublishedCatalogueQueryState({
    this.search = '',
    this.activeSearch = '',
    this.kind = PublishedKindFilter.all,
    this.language,
    this.sort = PublishedSortOrder.publishedOrder,
  });

  /// The text currently in the search field (not yet necessarily applied).
  final String search;

  /// The debounced term the engine runs.
  final String activeSearch;

  /// Kind chip selection.
  final PublishedKindFilter kind;

  /// Language facet, or null for "All languages".
  final String? language;

  /// Sort selection.
  final PublishedSortOrder sort;

  /// The pure-engine query this state represents.
  PublishedCatalogueQuery get activeQuery => PublishedCatalogueQuery(
    search: activeSearch,
    kind: kind,
    language: language,
    sort: sort,
  );

  /// True when a search text or facet is active (for the "No matches" action).
  bool get hasActiveFilter =>
      search.trim().isNotEmpty ||
      kind != PublishedKindFilter.all ||
      language != null;

  /// Returns a copy with the given fields replaced. [clearLanguage] exists
  /// because null ("all languages") is a real value, not "unchanged".
  PublishedCatalogueQueryState copyWith({
    String? search,
    String? activeSearch,
    PublishedKindFilter? kind,
    String? language,
    PublishedSortOrder? sort,
    bool clearLanguage = false,
  }) => PublishedCatalogueQueryState(
    search: search ?? this.search,
    activeSearch: activeSearch ?? this.activeSearch,
    kind: kind ?? this.kind,
    language: clearLanguage ? null : (language ?? this.language),
    sort: sort ?? this.sort,
  );
}
