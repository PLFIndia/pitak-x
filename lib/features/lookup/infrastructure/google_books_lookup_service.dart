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
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Google Books-backed lookup. Inject `client` in tests; `baseUrl` overridable.
final class GoogleBooksLookupService implements IsbnLookupService {
  /// Creates the service with a shared [client].
  GoogleBooksLookupService({required http.Client client, Uri? baseUrl})
    : _client = client,
      _base = baseUrl ?? Uri.parse('https://www.googleapis.com');

  final http.Client _client;
  final Uri _base;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    try {
      final items = await _volumes('isbn:$isbn', maxResults: 1);
      if (items == null) return const LookupNetworkError('request failed');
      if (items.isEmpty) return const LookupNotFound();
      final info = (items.first['volumeInfo'] as Map?)?.cast<String, dynamic>();
      if (info == null) return const LookupNotFound();
      return LookupFound(_toMetadata(info, isbn));
    } on Exception catch (e) {
      return LookupNetworkError('$e');
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
    } on Exception catch (e) {
      return SearchNetworkError('$e');
    }
  }

  /// Runs a `volumes` query; returns the items list, [] for none, or null on a
  /// non-2xx HTTP status (caller maps to a network error).
  Future<List<Map<String, dynamic>>?> _volumes(
    String q, {
    required int maxResults,
  }) async {
    final uri = _base.replace(
      path: '/books/v1/volumes',
      queryParameters: {'q': q, 'maxResults': '$maxResults'},
    );
    final resp = await _client.get(uri);
    if (resp.statusCode >= 400) return null;
    final body = jsonDecode(resp.body);
    if (body is! Map || body['items'] is! List) {
      return <Map<String, dynamic>>[];
    }
    return (body['items'] as List)
        .whereType<Map<String, dynamic>>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  BookMetadata _toMetadata(Map<String, dynamic> info, String isbn) {
    final authors = (info['authors'] as List?)?.whereType<String>().toList();
    final categories = (info['categories'] as List?)
        ?.whereType<String>()
        .take(3)
        .toList();
    final images = (info['imageLinks'] as Map?)?.cast<String, dynamic>();
    return BookMetadata(
      isbn: isbn,
      title: _combineTitle(
        info['title'] as String?,
        info['subtitle'] as String?,
      ),
      author: (authors == null || authors.isEmpty) ? null : authors.join(', '),
      publisher: info['publisher'] as String?,
      publishedYear: _extractYear(info['publishedDate'] as String?),
      pageCount: info['pageCount'] as int?,
      coverUrl: images == null
          ? null
          : (images['thumbnail'] ?? images['smallThumbnail']) as String?,
      genre: (categories == null || categories.isEmpty)
          ? null
          : categories.join(', '),
      language: info['language'] as String?,
    );
  }

  TitleSearchResult? _itemToResult(Map<String, dynamic> item) {
    final info = (item['volumeInfo'] as Map?)?.cast<String, dynamic>();
    final title = (info?['title'] as String?)?.trim();
    if (info == null || title == null || title.isEmpty) return null;
    final authors = (info['authors'] as List?)?.whereType<String>();
    final ids = (info['industryIdentifiers'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((m) => m['identifier'] as String?)
        .whereType<String>();
    final images = (info['imageLinks'] as Map?)?.cast<String, dynamic>();
    return TitleSearchResult(
      sourceKey: (item['id'] as String?) ?? title,
      title: title,
      author: (authors == null || authors.isEmpty) ? null : authors.first,
      publishedYear: _extractYear(info['publishedDate'] as String?),
      isbn: ids
          ?.firstWhere(
            (s) => s.length == 13 || s.length == 10,
            orElse: () => '',
          )
          .let((s) => s.isEmpty ? null : s),
      coverUrl: images == null
          ? null
          : (images['thumbnail'] ?? images['smallThumbnail']) as String?,
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

/// Small functional helper for nullable transforms (Kotlin's `let`).
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
