import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';

void main() {
  const isbn = '9780140449136';

  GoogleBooksLookupService withClient(
    Future<http.Response> Function(http.Request) handler, {
    Future<String?> Function()? apiKey,
  }) => GoogleBooksLookupService(client: MockClient(handler), apiKey: apiKey);

  group('user API key', () {
    test('is sent as the key query parameter when present', () async {
      String? seenKey;
      final svc = withClient((req) async {
        seenKey = req.url.queryParameters['key'];
        return http.Response('{"items": []}', 200);
      }, apiKey: () async => 'AIzaSyB-user-key');
      await svc.lookupByIsbn(isbn);
      expect(seenKey, 'AIzaSyB-user-key');
    });

    test('is omitted entirely when not set', () async {
      var hadKeyParam = true;
      final svc = withClient((req) async {
        hadKeyParam = req.url.queryParameters.containsKey('key');
        return http.Response('{"items": []}', 200);
      });
      await svc.lookupByIsbn(isbn);
      expect(hadKeyParam, isFalse);
    });

    test('is read per-request — a newly saved key applies', () async {
      String? stored; // starts unset
      final seen = <String?>[];
      final svc = withClient((req) async {
        seen.add(req.url.queryParameters['key']);
        return http.Response('{"items": []}', 200);
      }, apiKey: () async => stored);
      await svc.lookupByIsbn(isbn);
      stored = 'AIzaSyB-added-later-1234'; // user saves a key in Settings
      await svc.lookupByIsbn(isbn);
      expect(seen, [null, 'AIzaSyB-added-later-1234']);
    });
  });

  group('GoogleBooksLookupService.lookupByIsbn', () {
    test('parses a found volume', () async {
      final svc = withClient((req) async {
        expect(req.url.path, '/books/v1/volumes');
        expect(req.url.queryParameters['q'], 'isbn:$isbn');
        return http.Response('''
{"items": [
  {"id": "abc", "volumeInfo": {
    "title": "The Odyssey", "authors": ["Homer"], "publisher": "Penguin",
    "publishedDate": "2003-03-01", "pageCount": 560, "language": "en",
    "categories": ["Epic"], "imageLinks": {"thumbnail": "https://x/t.jpg"}
  }}
]}
''', 200);
      });
      final result = await svc.lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      final m = (result as LookupFound).metadata;
      expect(m.title, 'The Odyssey');
      expect(m.author, 'Homer');
      expect(m.publishedYear, 2003);
      expect(m.language, 'en');
      expect(m.coverUrl, 'https://x/t.jpg');
    });

    test('no items → NotFound', () async {
      final svc = withClient((_) async => http.Response('{"items": []}', 200));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNotFound>());
    });

    test('500 → NetworkError', () async {
      final svc = withClient((_) async => http.Response('', 500));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNetworkError>());
    });
  });

  group('GoogleBooksLookupService.searchByTitle', () {
    test('parses items into results', () async {
      final svc = withClient((req) async {
        expect(req.url.queryParameters['q'], 'intitle:odyssey');
        return http.Response('''
{"items": [
  {"id": "abc", "volumeInfo": {
    "title": "Odyssey", "authors": ["Homer"],
    "industryIdentifiers": [{"type": "ISBN_13", "identifier": "9780140449136"}]
  }}
]}
''', 200);
      });
      final result = await svc.searchByTitle('odyssey');
      expect(result, isA<SearchFound>());
      final r = (result as SearchFound).results.single;
      expect(r.title, 'Odyssey');
      expect(r.isbn, '9780140449136');
    });
  });
}
