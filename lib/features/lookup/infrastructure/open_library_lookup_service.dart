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
      final body = jsonDecode(resp.body);
      if (body is! Map || body[bibkey] is! Map) return const LookupNotFound();
      final dto = (body[bibkey] as Map).cast<String, dynamic>();
      return LookupFound(_toMetadata(dto, isbn));
    } on Exception catch (e) {
      return LookupNetworkError('$e');
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
      final body = jsonDecode(resp.body);
      if (body is! Map || body['docs'] is! List) return const SearchEmpty();
      final docs = (body['docs'] as List)
          .whereType<Map<String, dynamic>>()
          .map((d) => _docToResult(d.cast<String, dynamic>()))
          .whereType<TitleSearchResult>()
          .toList();
      return docs.isEmpty ? const SearchEmpty() : SearchFound(docs);
    } on Exception catch (e) {
      return SearchNetworkError('$e');
    }
  }

  BookMetadata _toMetadata(Map<String, dynamic> dto, String isbn) {
    final authors = (dto['authors'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((a) => a['name'] as String?)
        .whereType<String>()
        .toList();
    final publishers = (dto['publishers'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((p) => p['name'] as String?)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    final subjects = (dto['subjects'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((s) => s['name'] as String?)
        .whereType<String>()
        .take(3)
        .toList();
    final cover = (dto['cover'] as Map?)?.cast<String, dynamic>();
    return BookMetadata(
      isbn: isbn,
      title: _combineTitle(dto['title'] as String?, dto['subtitle'] as String?),
      author: (authors == null || authors.isEmpty) ? null : authors.join(', '),
      publisher: (publishers == null || publishers.isEmpty)
          ? null
          : publishers.first,
      publishedYear: _extractYear(dto['publish_date'] as String?),
      pageCount: dto['number_of_pages'] as int?,
      coverUrl: cover == null
          ? null
          : (cover['medium'] ?? cover['large'] ?? cover['small']) as String?,
      genre: (subjects == null || subjects.isEmpty)
          ? null
          : subjects.join(', '),
    );
  }

  TitleSearchResult? _docToResult(Map<String, dynamic> d) {
    final title = (d['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;
    final authorNames = (d['author_name'] as List?)?.whereType<String>();
    final isbns = (d['isbn'] as List?)?.whereType<String>();
    final coverId = d['cover_i'];
    return TitleSearchResult(
      sourceKey: (d['key'] as String?) ?? title,
      title: title,
      author: (authorNames == null || authorNames.isEmpty)
          ? null
          : authorNames.first,
      publishedYear: d['first_publish_year'] as int?,
      isbn: isbns
          ?.firstWhere(
            (s) => s.length == 13 || s.length == 10,
            orElse: () => '',
          )
          .let((s) => s.isEmpty ? null : s),
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

/// Small functional helper for nullable transforms (Kotlin's `let`).
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
