import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';

/// The viewer's origin + directory policy (ADR 0015 V18, viewer plan S2).
///
/// `BookmarkUrl` answers "may this Pages host be contacted?". This policy adds
/// "…and is it still THIS library?" — the property that stops one saved site
/// from redirecting the reader into another library or another Pages host.
void main() {
  const github = 'https://kadugodi.github.io/pitak/';
  const cloudflare = 'https://kadugodi-library.pages.dev/';
  const subProject = 'https://kadugodi.github.io/pitak/kannada/';

  group('catalogueUrl', () {
    test('resolves the sibling books.json on GitHub and Cloudflare', () {
      expect(
        PublishedSiteUrlPolicy.catalogueUrl(github),
        'https://kadugodi.github.io/pitak/books.json',
      );
      expect(
        PublishedSiteUrlPolicy.catalogueUrl(cloudflare),
        'https://kadugodi-library.pages.dev/books.json',
      );
      // A non-root project path keeps its prefix (the trailing slash is what
      // makes resolve() land INSIDE the site).
      expect(
        PublishedSiteUrlPolicy.catalogueUrl(subProject),
        'https://kadugodi.github.io/pitak/kannada/books.json',
      );
    });

    test('requires an already-canonical site root', () {
      for (final bad in <String>[
        'https://kadugodi.github.io/pitak', // no trailing slash
        'HTTPS://kadugodi.github.io/pitak/', // not normalize()'s spelling
        'https://Kadugodi.github.io/pitak/',
        'https://kadugodi.github.io/pitak/index.html',
        'https://kadugodi.github.io/pitak/?utm=1',
        'https://kadugodi.github.io/pitak/#top',
        'http://kadugodi.github.io/pitak/',
        'https://kadugodi.example.com/pitak/',
        'https://user@kadugodi.github.io/pitak/',
        'https://kadugodi.github.io:8443/pitak/',
        'https://kadugodi.github.io/pitak/../other/',
        'not a url',
        '',
      ]) {
        expect(
          PublishedSiteUrlPolicy.catalogueUrl(bad),
          isNull,
          reason: 'must fail closed for "$bad"',
        );
      }
    });

    test('a canonical non-ASCII project path resolves', () {
      final site = Uri(
        scheme: 'https',
        host: 'kadugodi.github.io',
        path: '/ಚಂದ/',
      ).toString();
      final resolved = PublishedSiteUrlPolicy.catalogueUrl(site);
      expect(resolved, isNotNull);
      expect(resolved, endsWith('/books.json'));
    });
  });

  group('sanitizeForSite', () {
    void allowed(String candidate) {
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(github, candidate),
        candidate,
        reason: 'expected "$candidate" to stay requestable',
      );
    }

    void refused(String candidate) {
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(github, candidate),
        isNull,
        reason: 'expected "$candidate" to be refused',
      );
    }

    test('an in-directory file is returned verbatim', () {
      allowed('https://kadugodi.github.io/pitak/books.json');
      allowed('https://kadugodi.github.io/pitak/covers/a.jpg');
      allowed('https://kadugodi.github.io/pitak/');
      // Surrounding whitespace is trimmed exactly like BookmarkUrl.sanitize.
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(
          github,
          '  https://kadugodi.github.io/pitak/books.json  ',
        ),
        'https://kadugodi.github.io/pitak/books.json',
      );
    });

    test('a sibling directory with the same prefix text is refused', () {
      refused('https://kadugodi.github.io/pitak2/books.json');
      refused('https://kadugodi.github.io/pitak-old/books.json');
      refused('https://kadugodi.github.io/books.json');
    });

    test('the parent directory is refused', () {
      refused('https://kadugodi.github.io/');
      refused('https://kadugodi.github.io/other/books.json');
    });

    test('another Pages host is refused even on the allow-list', () {
      refused('https://someone-else.github.io/pitak/books.json');
      refused('https://someone-else.pages.dev/books.json');
      refused('https://kadugodi.github.io/pitak/x/../../../y/books.json');
    });

    test('another library on the same host is refused', () {
      refused('https://kadugodi.github.io/another-library/books.json');
    });

    test('query and fragment tricks are refused', () {
      refused('https://kadugodi.github.io/pitak/books.json?v=2');
      refused('https://kadugodi.github.io/pitak/books.json#x');
    });

    test('path traversal is refused — raw, encoded and doubled', () {
      refused('https://kadugodi.github.io/pitak/../secret/books.json');
      refused('https://kadugodi.github.io/pitak/%2e%2e/secret/books.json');
      refused('https://kadugodi.github.io/pitak/%2E%2E/secret/books.json');
      refused('https://kadugodi.github.io/pitak//secret/books.json');
      refused('https://kadugodi.github.io/pitak/./x/../../secret.json');
    });

    test('encoded separators and backslashes are refused', () {
      refused('https://kadugodi.github.io/pitak/a%2fb.json');
      refused('https://kadugodi.github.io/pitak/a%2Fb.json');
      refused(r'https://kadugodi.github.io/pitak/..\secret\x.json');
      refused(r'https://kadugodi.github.io/pitak/\secret\x.json');
    });

    test('malformed percent escapes never throw and never escape', () {
      // `Uri.parse` re-encodes a bare '%' as `%25` before we inspect the path,
      // so the string cannot become a separator or dot segment on the server.
      // The address is allowed verbatim (the server may answer 400) but it
      // still names a file INSIDE the saved library.
      for (final raw in <String>[
        'https://kadugodi.github.io/pitak/%zz.json',
        'https://kadugodi.github.io/pitak/%2.json',
        'https://kadugodi.github.io/pitak/%',
      ]) {
        final result = PublishedSiteUrlPolicy.sanitizeForSite(github, raw);
        expect(result, raw);
        expect(Uri.parse(result!).path, startsWith('/pitak/'));
      }
    });

    test('escapes that decode to invalid UTF-8 are refused, never thrown', () {
      // Syntactically valid `%XX` escapes whose BYTES are not UTF-8. The old
      // code validated only the syntax and then let the decoder throw, which
      // crashed cover rendering for a hostile payload.
      for (final raw in <String>[
        // A lone continuation-style byte: never valid UTF-8.
        'https://kadugodi.github.io/pitak/%FF.jpg',
        // The classic overlong encoding of '/'.
        'https://kadugodi.github.io/pitak/%C0%AF.jpg',
        // A truncated multibyte sequence (first two bytes of a 3-byte char).
        'https://kadugodi.github.io/pitak/%E2%82.jpg',
        'https://kadugodi.github.io/pitak/books%FF.json',
        'https://kadugodi.github.io/pitak/%C0%AF/secret.json',
      ]) {
        String? result;
        expect(
          () => result = PublishedSiteUrlPolicy.sanitizeForSite(github, raw),
          returnsNormally,
          reason: 'decoding "$raw" must not throw',
        );
        expect(result, isNull, reason: 'must refuse "$raw"');
      }
    });

    test('a valid multibyte escape still resolves inside the library', () {
      // The refusal above must be about INVALID UTF-8 only: a well-formed
      // sequence keeps working (the same one the publisher writes for Indic
      // cover leaves).
      const candidate =
          'https://kadugodi.github.io/pitak/%E0%B2%9A%E0%B2%82%E0%B2%A6.jpg';
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(github, candidate),
        candidate,
      );
      expect(
        Uri.parse(candidate).pathSegments.last,
        'ಚಂದ.jpg',
        reason: 'the bytes really are a valid UTF-8 file name',
      );
    });

    test('a traversal that lands back inside is allowed', () {
      // `pitak/x/../books.json` == `pitak/books.json`: still this library.
      allowed('https://kadugodi.github.io/pitak/x/../books.json');
      allowed('https://kadugodi.github.io/pitak/%2e/books.json');
    });

    test('scheme, userinfo, port and host policy all still apply', () {
      refused('http://kadugodi.github.io/pitak/books.json');
      refused('https://user@kadugodi.github.io/pitak/books.json');
      refused('https://kadugodi.github.io:8443/pitak/books.json');
      refused('https://evil.example/pitak/books.json');
      refused('javascript:alert(1)');
      refused('');
      refused('   ');
    });

    test('a canonical non-ASCII in-site path is allowed', () {
      final site = Uri(
        scheme: 'https',
        host: 'kadugodi.github.io',
        path: '/ಚಂದ/',
      ).toString();
      final candidate = Uri(
        scheme: 'https',
        host: 'kadugodi.github.io',
        path: '/ಚಂದ/covers/೧.jpg',
      ).toString();
      expect(
        PublishedSiteUrlPolicy.sanitizeForSite(site, candidate),
        candidate,
      );
    });

    test('an unusable saved site refuses everything', () {
      for (final badSite in <String>[
        'https://kadugodi.github.io/pitak', // not canonical
        'https://kadugodi.github.io/pitak/../',
        'https://evil.example/',
        '',
      ]) {
        expect(
          PublishedSiteUrlPolicy.sanitizeForSite(
            badSite,
            'https://kadugodi.github.io/pitak/books.json',
          ),
          isNull,
          reason: 'site "$badSite" must never authorize a request',
        );
      }
    });

    test('sanitizerFor is the tear-off the bounded fetcher wants', () {
      final sanitize = PublishedSiteUrlPolicy.sanitizerFor(cloudflare);
      expect(
        sanitize('https://kadugodi-library.pages.dev/books.json'),
        'https://kadugodi-library.pages.dev/books.json',
      );
      expect(sanitize('https://kadugodi.github.io/pitak/books.json'), isNull);
    });
  });
}
