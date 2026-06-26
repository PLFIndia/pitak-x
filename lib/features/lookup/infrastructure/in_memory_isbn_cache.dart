/// In-memory [IsbnCache] (infrastructure, AGENTS.md §3.3).
///
/// A process-lifetime map keyed by ISBN. ISBN metadata is non-secret public
/// data, so an in-memory cache is sufficient and avoids a new persistence
/// surface; the chained composer owns the TTL policy. Could be swapped for a
/// Drift-backed implementation later without touching callers (the [IsbnCache]
/// port is the seam). Held alive for the app session via a keepAlive provider.
library;

import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';

/// Simple session-scoped ISBN cache.
final class InMemoryIsbnCache implements IsbnCache {
  final Map<String, IsbnCacheEntry> _store = {};

  @override
  Future<IsbnCacheEntry?> get(String isbn) async => _store[isbn];

  @override
  Future<void> putFound(BookMetadata metadata, {required int fetchedAt}) async {
    _store[metadata.isbn] = IsbnCacheEntry(
      fetchedAt: fetchedAt,
      notFound: false,
      metadata: metadata,
    );
  }

  @override
  Future<void> putNotFound(String isbn, {required int fetchedAt}) async {
    _store[isbn] = IsbnCacheEntry(fetchedAt: fetchedAt, notFound: true);
  }
}
