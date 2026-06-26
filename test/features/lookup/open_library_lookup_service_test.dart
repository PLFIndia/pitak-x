import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/infrastructure/open_library_lookup_service.dart';

void main() {
  const isbn = '9780140449136';

  OpenLibraryLookupService withClient(
    Future<http.Response> Function(http.Request) handler,
  ) => OpenLibraryLookupService(client: MockClient(handler));

  group('OpenLibraryLookupService.lookupByIsbn', () {
    test('parses a found record', () async {
      final svc = withClient((req) async {
        expect(req.url.path, '/api/books');
        return http.Response('''
{
  "ISBN:$isbn": {
    "title": "The Odyssey",
    "subtitle": "A New Translation",
    "authors": [{"name": "Homer"}],
    "publishers": [{"name": "Penguin"}],
    "publish_date": "March 2003",
    "number_of_pages": 560,
    "cover": {"medium": "https://x/cover.jpg"},
    "subjects": [{"name": "Epic"}, {"name": "Greek"}]
  }
}
''', 200);
      });
      final result = await svc.lookupByIsbn(isbn);
      expect(result, isA<LookupFound>());
      final m = (result as LookupFound).metadata;
      expect(m.title, 'The Odyssey: A New Translation');
      expect(m.author, 'Homer');
      expect(m.publisher, 'Penguin');
      expect(m.publishedYear, 2003);
      expect(m.pageCount, 560);
      expect(m.coverUrl, 'https://x/cover.jpg');
      expect(m.genre, 'Epic, Greek');
    });

    test('empty body → NotFound', () async {
      final svc = withClient((_) async => http.Response('{}', 200));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNotFound>());
    });

    test('404 → NotFound', () async {
      final svc = withClient((_) async => http.Response('', 404));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNotFound>());
    });

    test('500 → NetworkError', () async {
      final svc = withClient((_) async => http.Response('', 500));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNetworkError>());
    });

    test('transport exception → NetworkError', () async {
      final svc = withClient((_) async => throw http.ClientException('boom'));
      expect(await svc.lookupByIsbn(isbn), isA<LookupNetworkError>());
    });
  });

  group('OpenLibraryLookupService.searchByTitle', () {
    test('parses docs into results', () async {
      final svc = withClient((req) async {
        expect(req.url.path, '/search.json');
        return http.Response('''
{"docs": [
  {"key": "/works/OL1W", "title": "Odyssey", "author_name": ["Homer"],
   "first_publish_year": 1900, "isbn": ["9780140449136"], "cover_i": 42}
]}
''', 200);
      });
      final result = await svc.searchByTitle('odyssey');
      expect(result, isA<SearchFound>());
      final r = (result as SearchFound).results.single;
      expect(r.title, 'Odyssey');
      expect(r.author, 'Homer');
      expect(r.isbn, '9780140449136');
      expect(r.coverUrl, contains('/b/id/42-M.jpg'));
    });

    test('no docs → Empty', () async {
      final svc = withClient((_) async => http.Response('{"docs": []}', 200));
      expect(await svc.searchByTitle('zzz'), isA<SearchEmpty>());
    });
  });
}
