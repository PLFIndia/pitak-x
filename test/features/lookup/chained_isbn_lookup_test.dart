import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/lookup/application/chained_isbn_lookup.dart';
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/entities/title_search_result.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Scriptable provider: returns the queued result for each method.
class _FakeService implements IsbnLookupService {
  _FakeService({this.lookup, this.search});
  LookupResult? lookup;
  SearchResult? search;
  int lookups = 0;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    lookups++;
    return lookup ?? const LookupNotFound();
  }

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async =>
      search ?? const SearchEmpty();
}

/// Simple in-memory cache.
class _MemCache implements IsbnCache {
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

void main() {
  const isbn = '9780140449136';
  const meta = BookMetadata(isbn: isbn, title: 'The Odyssey');

  ChainedIsbnLookup chain(
    _FakeService primary,
    _FakeService fallback,
    _MemCache cache, {
    int now = 1000,
  }) => ChainedIsbnLookup(
    primary: primary,
    fallback: fallback,
    cache: cache,
    clock: () => now,
  );

  group('ChainedIsbnLookup.lookupByIsbn', () {
    test('primary Found is returned and cached', () async {
      final cache = _MemCache();
      final primary = _FakeService(lookup: const LookupFound(meta));
      final fallback = _FakeService();
      final result = await chain(primary, fallback, cache).lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      // Written through to cache.
      final cached = await cache.get(isbn);
      expect(cached?.metadata?.title, 'The Odyssey');
      // Fallback not consulted.
      expect(fallback.lookups, 0);
    });

    test('cache hit short-circuits before hitting providers', () async {
      final cache = _MemCache();
      await cache.putFound(meta, fetchedAt: 1000);
      final primary = _FakeService(lookup: const LookupNotFound());
      final fallback = _FakeService();
      final result = await chain(primary, fallback, cache).lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      expect(primary.lookups, 0);
    });

    test('primary NotFound falls through to fallback Found', () async {
      final cache = _MemCache();
      final primary = _FakeService(lookup: const LookupNotFound());
      final fallback = _FakeService(lookup: const LookupFound(meta));
      final result = await chain(primary, fallback, cache).lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      expect(fallback.lookups, 1);
    });

    test('both NotFound caches a NotFound sentinel', () async {
      final cache = _MemCache();
      final primary = _FakeService(lookup: const LookupNotFound());
      final fallback = _FakeService(lookup: const LookupNotFound());
      final result = await chain(primary, fallback, cache).lookupByIsbn(isbn);
      expect(result, isA<LookupNotFound>());
      final cached = await cache.get(isbn);
      expect(cached?.notFound, isTrue);
    });

    test(
      'primary error + fallback NotFound returns NetworkError, no cache',
      () async {
        final cache = _MemCache();
        final primary = _FakeService(lookup: const LookupNetworkError('down'));
        final fallback = _FakeService(lookup: const LookupNotFound());
        final result = await chain(primary, fallback, cache).lookupByIsbn(isbn);
        expect(result, isA<LookupNetworkError>());
        // Must NOT cache a NotFound when a transient error occurred (offline).
        expect(await cache.get(isbn), isNull);
      },
    );

    test('stale NotFound sentinel is re-queried', () async {
      final cache = _MemCache();
      await cache.putNotFound(isbn, fetchedAt: 0);
      final primary = _FakeService(lookup: const LookupFound(meta));
      final fallback = _FakeService();
      // now is well past the 24h NotFound TTL.
      final result = await chain(
        primary,
        fallback,
        cache,
        now: ChainedIsbnLookup.notFoundTtlMs + 1,
      ).lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      expect(primary.lookups, 1);
    });
  });

  group('ChainedIsbnLookup.searchByTitle', () {
    test('primary Found dedups by ISBN', () async {
      final cache = _MemCache();
      final primary = _FakeService(
        search: const SearchFound([
          TitleSearchResult(sourceKey: 'a', title: 'A', isbn: 'x'),
          TitleSearchResult(sourceKey: 'b', title: 'B', isbn: 'x'),
          TitleSearchResult(sourceKey: 'c', title: 'C'),
        ]),
      );
      final result = await chain(
        primary,
        _FakeService(),
        cache,
      ).searchByTitle('homer');
      expect(result, isA<SearchFound>());
      expect((result as SearchFound).results.length, 2);
    });

    test('primary Empty falls through to fallback Found', () async {
      final cache = _MemCache();
      final primary = _FakeService(search: const SearchEmpty());
      final fallback = _FakeService(
        search: const SearchFound([
          TitleSearchResult(sourceKey: 'a', title: 'A'),
        ]),
      );
      final result = await chain(
        primary,
        fallback,
        cache,
      ).searchByTitle('homer');
      expect(result, isA<SearchFound>());
    });

    test('primary error + fallback empty returns NetworkError', () async {
      final cache = _MemCache();
      final primary = _FakeService(search: const SearchNetworkError('down'));
      final fallback = _FakeService(search: const SearchEmpty());
      final result = await chain(
        primary,
        fallback,
        cache,
      ).searchByTitle('homer');
      expect(result, isA<SearchNetworkError>());
    });
  });
}
