import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_published_site_verifier.dart';

/// R16: publish read-back is bound to the EXACT published site — same origin,
/// same directory, no redirects, byte caps — and the cache-buster is the only
/// relaxation, available only through the publish-specific URL builder.
void main() {
  const site = 'https://me.github.io/lib/';

  group('PublishedSiteUrlPolicy.readBackUrl', () {
    test('joins the site root and a fixed path', () {
      expect(
        PublishedSiteUrlPolicy.readBackUrl(site, 'books.json'),
        'https://me.github.io/lib/books.json',
      );
    });

    test('appends exactly one rb cache-buster', () {
      expect(
        PublishedSiteUrlPolicy.readBackUrl(
          site,
          'books.json',
          cacheBuster: 'a1',
        ),
        'https://me.github.io/lib/books.json?rb=a1',
      );
    });

    test('refuses an unsafe or over-long cache-buster', () {
      for (final buster in ['a b', 'a&b=1', 'a#frag', '', 'x' * 65, 'é']) {
        expect(
          PublishedSiteUrlPolicy.readBackUrl(
            site,
            'books.json',
            cacheBuster: buster,
          ),
          isNull,
          reason: buster,
        );
      }
    });

    test('refuses traversal, absolute and multi-segment paths', () {
      for (final path in [
        '/books.json',
        '../books.json',
        'a/../../books.json',
        'a//b.json',
        r'a\b.json',
        'a/b/c/d.json',
      ]) {
        expect(
          PublishedSiteUrlPolicy.readBackUrl(site, path),
          isNull,
          reason: path,
        );
      }
    });

    test('an empty path is the canonical site root (moved pages)', () {
      // S9: the moved page is served AT the root, so `''` must resolve to the
      // site URL instead of being treated as an unsafe relative path.
      expect(PublishedSiteUrlPolicy.readBackUrl(site, ''), site);
      expect(
        PublishedSiteUrlPolicy.readBackUrl(site, '', cacheBuster: 'abc'),
        '$site?rb=abc',
      );
    });

    test('refuses a site root that is not canonical', () {
      expect(
        PublishedSiteUrlPolicy.readBackUrl(
          'https://me.github.io/lib',
          'books.json',
        ),
        isNull,
      );
      expect(
        PublishedSiteUrlPolicy.readBackUrl(
          'http://me.github.io/lib/',
          'books.json',
        ),
        isNull,
      );
    });

    test('the VIEWER policy is untouched: no query ever passes', () {
      // The whole point of the separate builder: sanitizeForSite keeps
      // refusing queries, so a redirect or a saved file URL cannot carry one.
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(
          site,
          'https://me.github.io/lib/books.json?rb=1',
        ),
        isNull,
      );
    });
  });

  group('BoundedPublishedSiteVerifier', () {
    test('returns the bytes of the exact URL', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([1, 2, 3], 200);
      });

      final bytes = await BoundedPublishedSiteVerifier(
        client: client,
      ).read(siteUrl: site, path: 'books.json', maxBytes: 16);

      expect(bytes, [1, 2, 3]);
      expect(requested, ['https://me.github.io/lib/books.json']);
    });

    test('passes the cache-buster through', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([1], 200);
      });

      await BoundedPublishedSiteVerifier(client: client).read(
        siteUrl: site,
        path: 'library.json',
        maxBytes: 16,
        cacheBuster: 'r1-0',
      );

      expect(requested.single, 'https://me.github.io/lib/library.json?rb=r1-0');
    });

    test('SECURITY: a redirect is refused, never followed', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example.com/books.json'},
        );
      });

      final bytes = await BoundedPublishedSiteVerifier(
        client: client,
      ).read(siteUrl: site, path: 'books.json', maxBytes: 16);

      expect(bytes, isNull);
      expect(requested, hasLength(1), reason: 'no hop was followed');
    });

    test('an over-cap body is refused', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(List.filled(64, 7), 200),
      );
      final bytes = await BoundedPublishedSiteVerifier(
        client: client,
      ).read(siteUrl: site, path: 'books.json', maxBytes: 8);
      expect(bytes, isNull);
    });

    test('a non-2xx answer is refused', () async {
      final client = MockClient((_) async => http.Response('nope', 404));
      expect(
        await BoundedPublishedSiteVerifier(
          client: client,
        ).read(siteUrl: site, path: 'events.json', maxBytes: 16),
        isNull,
      );
    });

    test('a refused URL never reaches the network', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes([1], 200);
      });
      final verifier = BoundedPublishedSiteVerifier(client: client);

      for (final (root, path) in [
        (site, '../other/books.json'),
        (site, 'a/../../books.json'),
        ('https://me.github.io/lib', 'books.json'),
        ('http://me.github.io/lib/', 'books.json'),
      ]) {
        expect(
          await verifier.read(siteUrl: root, path: path, maxBytes: 16),
          isNull,
          reason: '$root$path',
        );
      }
      expect(calls, 0);
    });

    test('a zero cap is refused before any request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes([], 200);
      });
      expect(
        await BoundedPublishedSiteVerifier(
          client: client,
        ).read(siteUrl: site, path: 'books.json', maxBytes: 0),
        isNull,
      );
      expect(calls, 0);
    });

    test(
      'structured reads distinguish a real 404 from other failures',
      () async {
        Future<PublishedSiteReadOutcome> withStatus(int status) =>
            BoundedPublishedSiteVerifier(
              client: MockClient((_) async => http.Response('no', status)),
            ).readOutcome(siteUrl: site, path: 'books.json', maxBytes: 16);

        expect(await withStatus(404), isA<PublishedSiteReadAbsent>());
        expect(await withStatus(500), isA<PublishedSiteReadUnreadable>());
      },
    );

    test('structured reads preserve bounded success bytes', () async {
      final outcome = await BoundedPublishedSiteVerifier(
        client: MockClient((_) async => http.Response.bytes([1, 2], 200)),
      ).readOutcome(siteUrl: site, path: 'books.json', maxBytes: 2);

      expect(outcome, isA<PublishedSiteReadBody>());
      expect((outcome as PublishedSiteReadBody).bytes, [1, 2]);
    });
  });
}
