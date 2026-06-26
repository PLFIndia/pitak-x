import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';

void main() {
  const isbn = '9780140449136';

  GoogleBooksLookupService withClient(
    Future<http.Response> Function(http.Request) handler,
  ) => GoogleBooksLookupService(client: MockClient(handler));

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
