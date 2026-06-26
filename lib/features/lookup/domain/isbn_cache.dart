/// Cache port for ISBN lookups (domain, AGENTS.md §3.3).
///
/// Keyed by ISBN. Stores either a Found metadata record or a NotFound sentinel
/// (with its fetch timestamp); the chained composer applies the TTL policy.
/// Declared in domain, implemented in infrastructure (in-memory for now; could
/// be Drift-backed later without touching callers). Searches are not cached.
library;

import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';

/// A cached ISBN entry: either [metadata] (Found) or a NotFound sentinel.
final class IsbnCacheEntry {
  /// Creates a cache entry. [notFound] true ⇒ a negative sentinel ([metadata]
  /// is null); otherwise [metadata] holds the cached record.
  const IsbnCacheEntry({
    required this.fetchedAt,
    required this.notFound,
    this.metadata,
  });

  /// Epoch millis when this entry was written.
  final int fetchedAt;

  /// True when this is a "no provider knew it" sentinel.
  final bool notFound;

  /// The cached metadata, or null for a NotFound sentinel.
  final BookMetadata? metadata;
}

/// TTL-agnostic ISBN cache. The composer decides freshness.
abstract interface class IsbnCache {
  /// Returns the cached entry for [isbn], or null when absent.
  Future<IsbnCacheEntry?> get(String isbn);

  /// Caches a Found [metadata] record stamped [fetchedAt].
  Future<void> putFound(BookMetadata metadata, {required int fetchedAt});

  /// Caches a NotFound sentinel for [isbn] stamped [fetchedAt].
  Future<void> putNotFound(String isbn, {required int fetchedAt});
}
