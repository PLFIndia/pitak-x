/// Chained ISBN lookup composer (application layer, AGENTS.md §4).
///
/// Port of Kotlin `ChainedIsbnLookup` (adapted, credited in PLAN.md): runs an
/// ISBN lookup against a cache, then a primary, then a fallback provider in
/// order, and a title search against primary→fallback. Mirrors the source
/// behaviour:
///  - cache hit within TTL → return Found from cache;
///  - a cached NotFound sentinel (shorter TTL) short-circuits to NotFound;
///  - primary Found → write-through + return; primary NotFound/NetworkError →
///    try fallback; any Found → write-through; both NotFound → cache NotFound
///    ONLY when no transient error was seen (offline ≠ definitively missing);
///  - title search: primary, then fallback on Empty/NetworkError, de-duped by
///    ISBN. Searches are not cached.
///
/// Providers never throw (graceful degradation), so this composer doesn't
/// either — it only branches on the sealed result types.
library;

import 'package:pitaka/features/lookup/domain/entities/title_search_result.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Composes two [IsbnLookupService]s with a cache in front (D7 fallback chain).
final class ChainedIsbnLookup implements IsbnLookupService {
  /// Creates the chain. [clock] defaults to the wall clock; inject in tests.
  ChainedIsbnLookup({
    required IsbnLookupService primary,
    required IsbnLookupService fallback,
    required IsbnCache cache,
    int Function()? clock,
  }) : _primary = primary,
       _fallback = fallback,
       _cache = cache,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final IsbnLookupService _primary;
  final IsbnLookupService _fallback;
  final IsbnCache _cache;
  final int Function() _clock;

  /// TTL for a cached Found record (7 days), mirroring the source default.
  static const int foundTtlMs = 7 * 24 * 60 * 60 * 1000;

  /// TTL for a cached NotFound sentinel (24h): short so a book newly added to
  /// a provider is recovered within a day, long enough to spare repeat misses.
  static const int notFoundTtlMs = 24 * 60 * 60 * 1000;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    final now = _clock();
    final cached = await _cache.get(isbn);
    if (cached != null) {
      if (cached.notFound) {
        if (now - cached.fetchedAt < notFoundTtlMs) {
          return const LookupNotFound();
        }
        // Stale NotFound — fall through and re-query.
      } else if (cached.metadata != null &&
          now - cached.fetchedAt < foundTtlMs) {
        return LookupFound(cached.metadata!);
      }
    }

    String? firstError;

    final primary = await _primary.lookupByIsbn(isbn);
    switch (primary) {
      case LookupFound(:final metadata):
        await _cache.putFound(metadata, fetchedAt: now);
        return LookupFound(metadata);
      case LookupNotFound():
        break;
      case LookupNetworkError(:final reason):
        firstError = reason ?? 'primary network error';
    }

    final fallback = await _fallback.lookupByIsbn(isbn);
    switch (fallback) {
      case LookupFound(:final metadata):
        await _cache.putFound(metadata, fetchedAt: now);
        return LookupFound(metadata);
      case LookupNotFound():
        // Both responded definitively negative. Cache the NotFound ONLY if no
        // transient error happened (otherwise the user might be offline).
        if (firstError != null) {
          return LookupNetworkError(firstError);
        }
        await _cache.putNotFound(isbn, fetchedAt: now);
        return const LookupNotFound();
      case LookupNetworkError(:final reason):
        return LookupNetworkError(firstError ?? reason);
    }
  }

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async {
    final primary = await _primary.searchByTitle(query, limit: limit);
    switch (primary) {
      case SearchFound(:final results):
        return SearchFound(_dedupByIsbn(results));
      case SearchEmpty():
        // Primary gave a clean Empty; try the fallback before giving up (D7).
        final fb = await _fallback.searchByTitle(query, limit: limit);
        return switch (fb) {
          SearchFound(:final results) => SearchFound(_dedupByIsbn(results)),
          SearchEmpty() => const SearchEmpty(),
          // Primary already said Empty cleanly — honour that.
          SearchNetworkError() => const SearchEmpty(),
        };
      case SearchNetworkError(:final reason):
        final fb = await _fallback.searchByTitle(query, limit: limit);
        return switch (fb) {
          SearchFound(:final results) => SearchFound(_dedupByIsbn(results)),
          SearchEmpty() => SearchNetworkError(reason),
          SearchNetworkError(reason: final fbReason) => SearchNetworkError(
            reason ?? fbReason,
          ),
        };
    }
  }

  List<TitleSearchResult> _dedupByIsbn(List<TitleSearchResult> results) {
    final seen = <String>{};
    return [
      for (final r in results)
        if (r.isbn == null || seen.add(r.isbn!)) r,
    ];
  }
}
