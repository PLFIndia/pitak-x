/// Result types for ISBN lookup + title search (pure domain, AGENTS.md §3.1).
///
/// Mirrors Kotlin `LookupResult` / `SearchResult`. These are EXPECTED outcomes
/// (found / not-found / empty / transient network error), not `Failure`s — the
/// chained-fallback logic branches on them, and the UI maps them to states
/// (offer title search on NotFound/NetworkError, etc.). Using a dedicated
/// sealed result keeps that control flow explicit rather than overloading the
/// app-wide `Either<Failure, T>` (which is for cross-layer error propagation).
///
/// Per the graceful-degradation rule: providers NEVER throw to the caller — a
/// network failure becomes [LookupNetworkError], an upstream shape mismatch
/// becomes [LookupNotFound] / [SearchEmpty].
library;

import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/entities/title_search_result.dart';

/// Outcome of an ISBN lookup.
sealed class LookupResult {
  const LookupResult();
}

/// A record was found.
final class LookupFound extends LookupResult {
  /// Wraps the found [metadata].
  const LookupFound(this.metadata);

  /// The looked-up metadata.
  final BookMetadata metadata;
}

/// No provider knew this ISBN (definitive negative).
final class LookupNotFound extends LookupResult {
  /// Creates a not-found result.
  const LookupNotFound();
}

/// A transient network error (the user may be offline; not cached).
final class LookupNetworkError extends LookupResult {
  /// Creates a network-error result with an optional [reason] (never shown
  /// verbatim to users).
  const LookupNetworkError([this.reason]);

  /// Short diagnostic; not user-facing.
  final String? reason;
}

/// Outcome of a title search.
sealed class SearchResult {
  const SearchResult();
}

/// One or more results were found.
final class SearchFound extends SearchResult {
  /// Wraps the [results] (already de-duplicated by ISBN).
  const SearchFound(this.results);

  /// The (non-empty) result rows.
  final List<TitleSearchResult> results;
}

/// The search ran but matched nothing.
final class SearchEmpty extends SearchResult {
  /// Creates an empty-search result.
  const SearchEmpty();
}

/// A transient network error during search.
final class SearchNetworkError extends SearchResult {
  /// Creates a network-error result with an optional [reason].
  const SearchNetworkError([this.reason]);

  /// Short diagnostic; not user-facing.
  final String? reason;
}
