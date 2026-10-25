import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';

/// The two cover origin policies (ADR 0015 V11/V18, viewer plan S5). Every
/// case here proves a request is NEVER made for a reference the policy does not
/// cover, and that the accepted URL is exactly the expected absolute one.
void main() {
  const github = 'https://kadugodi.github.io/pitak/';
  const cloudflare = 'https://kadugodi-library.pages.dev/';
  const subProject = 'https://kadugodi.github.io/pitak/kannada/';

  group('same-site relative covers', () {
    test('resolve against the GitHub and Cloudflare roots', () {
      final githubRequest = PublishedCoverResolver.resolve(
        github,
        'covers/abc.jpg',
      );
      expect(githubRequest, isA<SameSiteCoverRequest>());
      expect(
        githubRequest!.url,
        'https://kadugodi.github.io/pitak/covers/abc.jpg',
      );

      final cloudflareRequest = PublishedCoverResolver.resolve(
        cloudflare,
        'covers/abc.jpg',
      );
      expect(
        cloudflareRequest!.url,
        'https://kadugodi-library.pages.dev/covers/abc.jpg',
      );
    });

    test('a non-root project path keeps its prefix', () {
      expect(
        PublishedCoverResolver.resolve(subProject, 'covers/x.jpg')!.url,
        'https://kadugodi.github.io/pitak/kannada/covers/x.jpg',
      );
    });

    test('traversal, nesting, separators and smuggling are refused', () {
      for (final raw in <String>[
        'covers/../secret.jpg',
        'covers/a/b.jpg',
        'covers/',
        'covers/a%2fb.jpg',
        'covers/a%2Fb.jpg',
        'covers/%2e%2e/secret.jpg',
        r'covers/a\b.jpg',
        'covers/a.jpg?x=1',
        'covers/a.jpg#frag',
        'covers/a:b.jpg',
        'COVERS/a.jpg',
        'Covers/a.jpg',
        'cover/a.jpg',
      ]) {
        expect(
          PublishedCoverResolver.resolve(github, raw),
          isNull,
          reason: 'must not request "$raw"',
        );
      }
    });

    test('surrounding whitespace is trimmed like every sanitizer', () {
      expect(
        PublishedCoverResolver.resolve(github, '  covers/a.jpg  ')!.url,
        'https://kadugodi.github.io/pitak/covers/a.jpg',
      );
    });

    test('a unicode leaf is allowed and percent-encoded', () {
      final request = PublishedCoverResolver.resolve(github, 'covers/ಚಂದ.jpg');
      expect(request, isA<SameSiteCoverRequest>());
      expect(request!.url, contains('covers/'));
      // `pathSegments` is already decoded; the URL string itself is
      // percent-encoded on the wire.
      expect(Uri.parse(request.url).pathSegments.last, 'ಚಂದ.jpg');
      expect(request.url, contains('%E0%B2%9A'));
    });

    test('a same-site request refuses another host or directory', () {
      final request =
          PublishedCoverResolver.resolve(github, 'covers/a.jpg')!
              as SameSiteCoverRequest;
      expect(
        request.sanitize('https://kadugodi.github.io/pitak/covers/a.jpg'),
        isNotNull,
      );
      expect(
        request.sanitize('https://someone-else.github.io/pitak/covers/a.jpg'),
        isNull,
      );
      expect(
        request.sanitize('https://kadugodi.github.io/other/covers/a.jpg'),
        isNull,
      );
      expect(
        request.sanitize('https://kadugodi.github.io/pitak/%2e%2e/x.jpg'),
        isNull,
      );
    });
  });

  group('third-party absolute covers', () {
    test('allow-listed hosts classify as third-party requests', () {
      for (final url in <String>[
        'https://covers.openlibrary.org/b/id/1-L.jpg',
        'https://books.google.com/books/content?id=1',
        'https://books.googleusercontent.com/books/content?id=1',
        'https://archive.org/download/x/y.jpg',
        'https://ia123456.us.archive.org/view_archive.php?x=1',
      ]) {
        final request = PublishedCoverResolver.resolve(github, url);
        expect(request, isA<ThirdPartyCoverRequest>(), reason: url);
        expect(request!.url, url);
      }
    });

    test('any other absolute URL is refused', () {
      for (final url in <String>[
        'https://evil.example/a.jpg',
        'https://covers.openlibrary.org.evil.example/a.jpg',
        'https://covers.openlibrary.org:8443/a.jpg',
        'https://user@covers.openlibrary.org/a.jpg',
        'http://covers.openlibrary.org/a.jpg',
        // A Pages URL is NOT an allowed absolute cover just because Pitak can
        // read catalogues from Pages.
        'https://kadugodi.github.io/pitak/covers/a.jpg',
        'https://kadugodi-library.pages.dev/covers/a.jpg',
        // web.archive.org is deliberately not on the list.
        'https://web.archive.org/x.jpg',
      ]) {
        expect(
          PublishedCoverResolver.resolve(github, url),
          isNull,
          reason: 'must not request "$url"',
        );
      }
    });

    test(
      'a third-party request keeps the existing allow-list on every hop',
      () {
        final request =
            PublishedCoverResolver.resolve(
                  github,
                  'https://covers.openlibrary.org/b/id/1-L.jpg',
                )!
                as ThirdPartyCoverRequest;
        // The Open Library → Internet Archive path still works…
        expect(
          request.sanitize(
            'https://ia800000.us.archive.org/view_archive.php?x=1',
          ),
          isNotNull,
        );
        // …while anything outside the list is refused.
        expect(request.sanitize('https://evil.example/a.jpg'), isNull);
        expect(request.sanitize('https://kadugodi.github.io/a.jpg'), isNull);
      },
    );
  });

  group('blank input', () {
    test('null, empty and whitespace never request anything', () {
      for (final raw in <String?>[null, '', '   ']) {
        expect(PublishedCoverResolver.resolve(github, raw), isNull);
      }
    });
  });
}
