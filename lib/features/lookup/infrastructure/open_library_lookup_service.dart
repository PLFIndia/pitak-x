/// Open Library [IsbnLookupService] (infrastructure, AGENTS.md §3.3).
///
/// Port of the Kotlin `OpenLibraryApi` + `OpenLibraryLookupService` (adapted,
/// credited in PLAN.md). Public, no-auth REST:
///  - ISBN: GET /api/books?bibkeys=ISBN:{isbn}&format=json&jscmd=data
///  - title: GET /search.json?title={q}&limit={n}
///
/// Graceful degradation (never throws): any network/parse error →
/// `*NetworkError`; an empty/missing record → `NotFound` / `Empty`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/entities/title_search_result.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/json_coerce.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';

/// Open Library-backed lookup. Inject `client` in tests; `baseUrl` is
/// overridable for hermetic testing.
final class OpenLibraryLookupService implements IsbnLookupService {
  /// Creates the service. [client] defaults to a one-shot client per call is
  /// avoided — a shared client is injected (closed by its owner).
  OpenLibraryLookupService({required http.Client client, Uri? baseUrl})
    : _client = client,
      _base = baseUrl ?? Uri.parse('https://openlibrary.org');

  final http.Client _client;
  final Uri _base;

  @override
  Future<LookupResult> lookupByIsbn(String isbn) async {
    final bibkey = 'ISBN:$isbn';
    final uri = _base.replace(
      path: '/api/books',
      queryParameters: {'bibkeys': bibkey, 'format': 'json', 'jscmd': 'data'},
    );
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode == 404) return const LookupNotFound();
      if (resp.statusCode >= 400) {
        return LookupNetworkError('HTTP ${resp.statusCode}');
      }
      final body = jsonMap(jsonDecode(resp.body));
      final dto = body == null ? null : jsonMap(body[bibkey]);
      if (dto == null) return const LookupNotFound();
      return LookupFound(_toMetadata(dto, isbn));
    } on Object {
      // `on Object`: transport errors are Exceptions, but a hostile/garbled
      // body can surface as an Error (e.g. a cast failure deep in jsonDecode).
      // Either way the user-facing outcome is the same fixed message; the
      // reason string is deliberately NOT built from the error object because
      // `ClientException.toString()` includes the request URL.
      return const LookupNetworkError('request failed');
    }
  }

  @override
  Future<SearchResult> searchByTitle(String query, {int limit = 20}) async {
    final uri = _base.replace(
      path: '/search.json',
      queryParameters: {'title': query, 'limit': '$limit'},
    );
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode >= 400) {
        return SearchNetworkError('HTTP ${resp.statusCode}');
      }
      final body = jsonMap(jsonDecode(resp.body));
      if (body == null) return const SearchEmpty();
      final docs = jsonList(body['docs'])
          .map(jsonMap)
          .whereType<Map<String, dynamic>>()
          .map(_docToResult)
          .whereType<TitleSearchResult>()
          .toList();
      return docs.isEmpty ? const SearchEmpty() : SearchFound(docs);
    } on Object {
      return const SearchNetworkError('request failed');
    }
  }

  BookMetadata _toMetadata(Map<String, dynamic> dto, String isbn) {
    // Every field goes through the tolerant json* helpers: a wrong-typed value
    // becomes null instead of throwing `_TypeError` (an Error that `on
    // Exception` would NOT catch — see lookup/domain/json_coerce.dart).
    final authors = jsonList(dto['authors'])
        .map(jsonMap)
        .whereType<Map<String, dynamic>>()
        .map((a) => jsonString(a['name']))
        .whereType<String>()
        .toList();
    final publishers = jsonList(dto['publishers'])
        .map(jsonMap)
        .whereType<Map<String, dynamic>>()
        .map((p) => jsonString(p['name']))
        .whereType<String>()
        .toList();
    final subjects = jsonList(dto['subjects'])
        .map(jsonMap)
        .whereType<Map<String, dynamic>>()
        .map((s) => jsonString(s['name']))
        .whereType<String>()
        .take(3)
        .toList();
    final cover = jsonMap(dto['cover']);
    return BookMetadata(
      isbn: isbn,
      title: _combineTitle(
        jsonString(dto['title']),
        jsonString(dto['subtitle']),
      ),
      author: authors.isEmpty ? null : authors.join(', '),
      publisher: publishers.isEmpty ? null : publishers.first,
      publishedYear: _extractYear(jsonString(dto['publish_date'])),
      pageCount: jsonInt(dto['number_of_pages']),
      coverUrl: cover == null
          ? null
          : jsonString(cover['medium'] ?? cover['large'] ?? cover['small']),
      genre: subjects.isEmpty ? null : subjects.join(', '),
    );
  }

  TitleSearchResult? _docToResult(Map<String, dynamic> d) {
    final title = jsonString(d['title']);
    if (title == null) return null;
    final authorNames = jsonStringList(d['author_name']);
    final isbns = jsonStringList(d['isbn']);
    final coverId = jsonInt(d['cover_i']);
    final isbn = isbns.firstWhere(
      (s) => s.length == 13 || s.length == 10,
      orElse: () => '',
    );
    return TitleSearchResult(
      sourceKey: jsonString(d['key']) ?? title,
      title: title,
      author: authorNames.isEmpty ? null : authorNames.first,
      publishedYear: jsonInt(d['first_publish_year']),
      isbn: isbn.isEmpty ? null : isbn,
      // cover_i is an integer id; only a real int is interpolated into the URL
      // (a string here could smuggle path characters into the cover host).
      coverUrl: coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
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
