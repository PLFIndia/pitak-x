/// Google Books [IsbnLookupService] (infrastructure, AGENTS.md §3.3).
///
/// Port of the Kotlin `GoogleBooksApi` + service (adapted, credited in
/// PLAN.md). Public, no-auth v1 REST:
///  - ISBN:  GET /books/v1/volumes?q=isbn:{isbn}
///  - title: GET /books/v1/volumes?q=intitle:{q}&maxResults={n}
///
/// Graceful degradation (never throws): network/parse error → `*NetworkError`;
/// empty/missing record → `NotFound` / `Empty`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/entities/title_search_result.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/json_coerce.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Google Books-backed lookup. Inject `client` in tests; `baseUrl` overridable.
final class GoogleBooksLookupService implements IsbnLookupService {
  /// Creates the service with a shared [client]. [apiKey] (optional) returns
  /// the user's own Google API key or null — read per-request, so a key
  /// saved in Settings takes effect without rebuilding this service.
  GoogleBooksLookupService({
    required http.Client client,
    Uri? baseUrl,
    Future<String?> Function()? apiKey,
  }) : _client = client,
       _base = baseUrl ?? Uri.parse('https://www.googleapis.com'),
       _apiKey = apiKey ?? (() async => null);

  final http.Client _client;
  final Uri _base;
  final Future<String?> Function() _apiKey;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    try {
      final items = await _volumes('isbn:$isbn', maxResults: 1);
      if (items == null) return const LookupNetworkError('request failed');
      if (items.isEmpty) return const LookupNotFound();
      final info = jsonMap(items.first['volumeInfo']);
      if (info == null) return const LookupNotFound();
      return LookupFound(_toMetadata(info, isbn));
    } on Object {
      // `on Object`: a garbled body can raise an Error, not just an
      // Exception. Fixed reason string on purpose — the request URL carries
      // the user's API key and must never be stringified into a diagnostic.
      return const LookupNetworkError('request failed');
    }
  }

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async {
    try {
      final items = await _volumes('intitle:$query', maxResults: limit);
      if (items == null) return const SearchNetworkError('request failed');
      final results = items
          .map(_itemToResult)
          .whereType<TitleSearchResult>()
          .toList();
      return results.isEmpty ? const SearchEmpty() : SearchFound(results);
    } on Object {
      return const SearchNetworkError('request failed');
    }
  }

  /// Runs a `volumes` query; returns the items list, [] for none, or null on a
  /// non-2xx HTTP status (caller maps to a network error).
  Future<List<Map<String, dynamic>>?> _volumes(
    String q, {
    required int maxResults,
  }) async {
    // With a user key the request runs on THEIR dedicated free quota
    // (~1000/day) instead of Google's shared anonymous pool, which is often
    // exhausted globally (429 RESOURCE_EXHAUSTED).
    final key = await _apiKey();
    final uri = _base.replace(
      path: '/books/v1/volumes',
      queryParameters: {
        'q': q,
        'maxResults': '$maxResults',
        if (key != null) 'key': key,
      },
    );
    final resp = await _client.get(uri);
    if (resp.statusCode >= 400) return null;
    final body = jsonMap(jsonDecode(resp.body));
    if (body == null) return <Map<String, dynamic>>[];
    return jsonList(
      body['items'],
    ).map(jsonMap).whereType<Map<String, dynamic>>().toList();
  }

  BookMetadata _toMetadata(Map<String, dynamic> info, String isbn) {
    // Tolerant coercion throughout — see lookup/domain/json_coerce.dart.
    final authors = jsonStringList(info['authors']);
    final categories = jsonStringList(info['categories']).take(3).toList();
    final images = jsonMap(info['imageLinks']);
    return BookMetadata(
      isbn: isbn,
      title: _combineTitle(
        jsonString(info['title']),
        jsonString(info['subtitle']),
      ),
      author: authors.isEmpty ? null : authors.join(', '),
      publisher: jsonString(info['publisher']),
      publishedYear: _extractYear(jsonString(info['publishedDate'])),
      pageCount: jsonInt(info['pageCount']),
      coverUrl: images == null
          ? null
          : jsonString(images['thumbnail'] ?? images['smallThumbnail']),
      genre: categories.isEmpty ? null : categories.join(', '),
      language: jsonString(info['language']),
    );
  }

  TitleSearchResult? _itemToResult(Map<String, dynamic> item) {
    final info = jsonMap(item['volumeInfo']);
    final title = info == null ? null : jsonString(info['title']);
    if (info == null || title == null) return null;
    final authors = jsonStringList(info['authors']);
    final ids = jsonList(info['industryIdentifiers'])
        .map(jsonMap)
        .whereType<Map<String, dynamic>>()
        .map((m) => jsonString(m['identifier']))
        .whereType<String>()
        .toList();
    final images = jsonMap(info['imageLinks']);
    final isbn = ids.firstWhere(
      (s) => s.length == 13 || s.length == 10,
      orElse: () => '',
    );
    return TitleSearchResult(
      sourceKey: jsonString(item['id']) ?? title,
      title: title,
      author: authors.isEmpty ? null : authors.first,
      publishedYear: _extractYear(jsonString(info['publishedDate'])),
      isbn: isbn.isEmpty ? null : isbn,
      coverUrl: images == null
          ? null
          : jsonString(images['thumbnail'] ?? images['smallThumbnail']),
    );
  }

  static String? _combineTitle(String? title, String? subtitle) {
    final t = title?.trim() ?? '';
    final s = subtitle?.trim() ?? '';
    if (t.isNotEmpty && s.isNotEmpty) return '$t: $s';
    if (t.isNotEmpty) return t;
    if (s.isNotEmpty) return s;
    return null;
  }

  static final RegExp _yearRe = RegExp(r'\b(1[5-9]\d\d|20\d\d|21\d\d)\b');

  static int? _extractYear(String? s) {
    if (s == null) return null;
    final m = _yearRe.firstMatch(s);
    return m == null ? null : int.tryParse(m.group(0)!);
  }
}
