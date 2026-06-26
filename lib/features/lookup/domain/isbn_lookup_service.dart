/// Contract for an ISBN lookup provider (pure domain, AGENTS.md §3.1/§3.3).
///
/// Mirror of Kotlin `IsbnLookupService`. Implementations live in
/// `infrastructure/` (Open Library, Google Books) with a chained composer that
/// runs them in fallback order over a cache. Every method degrades gracefully:
/// network failure → `*NetworkError`, upstream shape mismatch → `NotFound` /
/// `Empty`. Never throws to the caller.
library;

import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// A provider that can look up a book by ISBN or search by title.
abstract interface class IsbnLookupService {
  /// Looks up a single [isbn] (expects the already-normalised form).
  Future<LookupResult> lookupByIsbn(String isbn);

  /// Searches by free-text [query] title, capped at [limit] rows.
  Future<SearchResult> searchByTitle(String query, {int limit = 20});
}
