/// The viewer's controls state (network application layer; viewer plan S3).
///
/// A synchronous, auto-dispose, screen-scoped notifier: the query intent must
/// survive opening an item detail and coming back, must NOT be persisted, and
/// must reset on a new mount. It never performs IO — changing a filter or a
/// sort only rebuilds the derived view.
///
/// Typed search is debounced 120 ms (the same contract as `LibraryController`)
/// so a burst of keystrokes starts at most one engine pass. The timer is the
/// viewer's ONLY timer besides the fetch deadline; it is cancelled on dispose
/// and it never triggers HTTP.
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_state.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_catalogue_query_controller.g.dart';

/// Debounce window before a typed search reaches the query engine (matches
/// the Library's 120 ms contract).
const publishedSearchDebounce = Duration(milliseconds: 120);

/// Holds the viewer's search/filter/sort intent for one library session.
@riverpod
class PublishedCatalogueQueryController
    extends _$PublishedCatalogueQueryController {
  Timer? _debounce;
  bool _disposed = false;

  @override
  PublishedCatalogueQueryState build(String siteUrl) {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _debounce = null;
    });
    return const PublishedCatalogueQueryState();
  }

  /// Updates the visible search text immediately and applies it after the
  /// debounce window. A newer keystroke always wins.
  void search(String text) {
    if (text == state.search) return;
    state = state.copyWith(search: text);
    _debounce?.cancel();
    _debounce = Timer(publishedSearchDebounce, () {
      // The provider may have been disposed between scheduling and firing.
      if (_disposed || state.search != text) return;
      state = state.copyWith(activeSearch: text);
    });
  }

  /// Selects a kind chip.
  void setKind(PublishedKindFilter kind) {
    if (state.kind == kind) return;
    state = state.copyWith(kind: kind);
  }

  /// Selects a language facet, or null for "All languages".
  void setLanguage(String? language) {
    if (state.language == language) return;
    state = state.copyWith(language: language, clearLanguage: language == null);
  }

  /// Selects a sort order.
  void setSort(PublishedSortOrder sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }

  /// Clears the search and both facets; keeps the sort. Used by the
  /// "No matches" action, which must NOT refetch anything.
  void clearFilters() {
    _debounce?.cancel();
    _debounce = null;
    state = PublishedCatalogueQueryState(sort: state.sort);
  }
}

/// The display view: the pure engine applied to the loaded catalogue and the
/// debounced query intent.
///
/// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
/// never on the UI isolate in production. Riverpod attributes each result to
/// the build that asked for it, so a late pass for an older intent cannot
/// overwrite a newer answer; the revision tests pin that behaviour.
@riverpod
Future<PublishedCatalogueView> publishedCatalogueView(
  PublishedCatalogueViewRef ref,
  String siteUrl,
) async {
  final catalogue = await ref.watch(
    publishedCatalogueControllerProvider(siteUrl).future,
  );
  // A RECORD select: structural equality keeps a filtering/sorting pass from
  // re-running on every keystroke (only the debounced active term is here).
  final intent = ref.watch(
    publishedCatalogueQueryControllerProvider(
      siteUrl,
    ).select((s) => (s.activeSearch, s.kind, s.language, s.sort)),
  );
  final runner = ref.watch(publishedCatalogueQueryRunnerProvider);
  return runner(
    catalogue,
    PublishedCatalogueQuery(
      search: intent.$1,
      kind: intent.$2,
      language: intent.$3,
      sort: intent.$4,
    ),
  );
}

/// The language facet for one catalogue: distinct trimmed values, sorted and
/// case-insensitively deduplicated. Computed once per decoded payload, not
/// once per query.
@riverpod
List<String> publishedCatalogueLanguages(
  PublishedCatalogueLanguagesRef ref,
  String siteUrl,
) {
  final catalogue = ref
      .watch(publishedCatalogueControllerProvider(siteUrl))
      .valueOrNull;
  if (catalogue == null) return const [];
  return PublishedQueryEngine.languagesOf(catalogue);
}
