/// ISBN-lookup DI bindings (AGENTS.md §4; SOLID-PLAN S3) — #29/#30.
///
/// What lives here: the session-scoped lookup cache, the encrypted API-key
/// store, and the chained lookup service (Open Library primary, Google Books
/// fallback). Only hit on explicit user action.
library;

import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/lookup/application/chained_isbn_lookup.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_key_store.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/in_memory_isbn_cache.dart';
import 'package:pitaka/features/lookup/infrastructure/open_library_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/secure_storage_lookup_key_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lookup_providers.g.dart';

/// Session-scoped ISBN lookup cache (#30). Non-secret public metadata.
@Riverpod(keepAlive: true)
IsbnCache isbnCache(IsbnCacheRef ref) => InMemoryIsbnCache();

/// Optional user-supplied Google Books API key (encrypted at rest, §6.3).
/// keepAlive: tiny, session-stable, and read on every lookup.
@Riverpod(keepAlive: true)
LookupKeyStore lookupKeyStore(LookupKeyStoreRef ref) =>
    SecureStorageLookupKeyStore();

/// ISBN lookup + title search (#29/#30): Open Library primary, Google Books
/// fallback, chained over the cache. Only hit on explicit user action.
@riverpod
IsbnLookupService isbnLookupService(IsbnLookupServiceRef ref) {
  final client = ref.watch(lookupHttpClientProvider);
  final keys = ref.watch(lookupKeyStoreProvider);
  return ChainedIsbnLookup(
    primary: OpenLibraryLookupService(client: client),
    fallback: GoogleBooksLookupService(
      client: client,
      // Read per-request: a key saved in Settings applies immediately.
      apiKey: keys.googleBooksApiKey,
    ),
    cache: ref.watch(isbnCacheProvider),
  );
}
