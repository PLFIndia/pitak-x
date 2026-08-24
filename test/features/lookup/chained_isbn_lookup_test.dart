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

/// Per-ISBN scriptable provider for the alternate-form (10↔13) tests.
class _PerIsbnService implements IsbnLookupService {
  _PerIsbnService(this.byIsbn);

  /// Result per exact ISBN; unknown ISBNs → NotFound.
  final Map<String, LookupResult> byIsbn;

  /// Every ISBN this service was asked for, in order.
  final List<String> asked = [];

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    asked.add(isbn);
    return byIsbn[isbn] ?? const LookupNotFound();
  }

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async =>
      const SearchEmpty();
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

  group('ChainedIsbnLookup alternate ISBN form (10↔13)', () {
    // 0140449132 ↔ 9780140449136 (same book, both structurally valid).
    const isbn10 = '0140449132';
    const isbn13 = '9780140449136';
    const meta13 = BookMetadata(isbn: isbn13, title: 'The Odyssey');

    ChainedIsbnLookup perIsbnChain(_PerIsbnService primary, _MemCache cache) =>
        ChainedIsbnLookup(
          primary: primary,
          fallback: _PerIsbnService({}),
          cache: cache,
          clock: () => 1000,
        );

    test('NotFound under ISBN-10 is rescued by the ISBN-13 form', () async {
      final primary = _PerIsbnService({isbn13: const LookupFound(meta13)});
      final result = await perIsbnChain(
        primary,
        _MemCache(),
      ).lookupByIsbn(isbn10);
      expect(result, isA<LookupFound>());
      expect((result as LookupFound).metadata.title, 'The Odyssey');
      expect(primary.asked, [isbn10, isbn13]);
    });

    test('NotFound under ISBN-13 is rescued by the ISBN-10 form', () async {
      const meta10 = BookMetadata(isbn: isbn10, title: 'The Odyssey');
      final primary = _PerIsbnService({isbn10: const LookupFound(meta10)});
      final result = await perIsbnChain(
        primary,
        _MemCache(),
      ).lookupByIsbn(isbn13);
      expect(result, isA<LookupFound>());
      expect(primary.asked, [isbn13, isbn10]);
    });

    test('both forms NotFound → NotFound (both sentinels cached)', () async {
      final cache = _MemCache();
      final result = await perIsbnChain(
        _PerIsbnService({}),
        cache,
      ).lookupByIsbn(isbn10);
      expect(result, isA<LookupNotFound>());
      expect((await cache.get(isbn10))?.notFound, isTrue);
      expect((await cache.get(isbn13))?.notFound, isTrue);
    });

    test('a 979-prefixed ISBN-13 has no alternate — single pass', () async {
      // Valid 979 ISBN-13; no ISBN-10 form exists.
      const isbn979 = '9791234567896';
      final primary = _PerIsbnService({});
      final result = await perIsbnChain(
        primary,
        _MemCache(),
      ).lookupByIsbn(isbn979);
      expect(result, isA<LookupNotFound>());
      expect(primary.asked, [isbn979]);
    });

    test('transient error on the original form is not masked by an '
        'alternate-form miss', () async {
      final primary = _PerIsbnService({
        isbn10: const LookupNetworkError('offline'),
      });
      // Fallback also errors for isbn10 → chain returns NetworkError for the
      // original; the alternate form must not run at all (result is not
      // NotFound), so no false NotFound reaches the user while offline.
      final chain = ChainedIsbnLookup(
        primary: primary,
        fallback: _PerIsbnService({
          isbn10: const LookupNetworkError('offline'),
        }),
        cache: _MemCache(),
        clock: () => 1000,
      );
      final result = await chain.lookupByIsbn(isbn10);
      expect(result, isA<LookupNetworkError>());
      expect(primary.asked, [isbn10]);
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
