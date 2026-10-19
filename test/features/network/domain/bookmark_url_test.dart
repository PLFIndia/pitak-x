import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// The allow-list cases carried over from the deleted bookmarks feature
/// (`test/features/bookmarks/library_bookmark_test.dart`, ADR 0012) plus the
/// canonical site-root rules added in the 2026-10 network review: the stored
/// `siteUrl` is the natural key of the network table AND the base every
/// `library.json` path is resolved against, so one site must have exactly
/// one spelling and it must end with `/`.
void main() {
  group('BookmarkUrl.normalize — accepted (canonical site root)', () {
    // (input, canonical output)
    const ok = <(String, String)>[
      (
        'https://myname.github.io/library/',
        'https://myname.github.io/library/',
      ),
      ('https://myname.github.io', 'https://myname.github.io/'),
      ('https://github.io', 'https://github.io/'), // bare apex
      ('https://lib.pages.dev/', 'https://lib.pages.dev/'),
      (
        'https://my-library.pages.dev/catalogue',
        'https://my-library.pages.dev/catalogue/',
      ),
      ('https://pages.dev', 'https://pages.dev/'),
    ];
    for (final (url, canonical) in ok) {
      test('accepts $url → $canonical', () {
        expect(BookmarkUrl.normalize(url), canonical);
        expect(BookmarkUrl.isValid(url), isTrue);
      });
    }

    test('trims surrounding whitespace', () {
      expect(
        BookmarkUrl.normalize('  https://x.github.io/  '),
        'https://x.github.io/',
      );
    });

    test('normalize is idempotent (canonical in ⇒ same canonical out)', () {
      const canonical = 'https://a.github.io/pitak/';
      expect(BookmarkUrl.normalize(canonical), canonical);
      expect(
        BookmarkUrl.normalize(
          BookmarkUrl.normalize('https://A.GitHub.io/pitak'),
        ),
        canonical,
      );
    });
  });

  group('BookmarkUrl.normalize — one site, one key (H3)', () {
    const canonical = 'https://a.github.io/pitak/';

    test('a missing trailing slash is added (the share card prints none)', () {
      expect(BookmarkUrl.normalize('https://a.github.io/pitak'), canonical);
    });

    test('scheme and host are lower-cased; the PATH keeps its case', () {
      expect(BookmarkUrl.normalize('HTTPS://A.GitHub.IO/pitak/'), canonical);
      expect(
        BookmarkUrl.normalize('https://a.github.io/Pitak/'),
        'https://a.github.io/Pitak/',
        reason: 'GitHub Pages paths are case-sensitive',
      );
    });

    test('query strings are dropped (no unlimited "different" rows)', () {
      expect(
        BookmarkUrl.normalize('https://a.github.io/pitak/?utm=1'),
        canonical,
      );
      expect(
        BookmarkUrl.normalize('https://a.github.io/pitak?x=1&y=2'),
        canonical,
      );
    });

    test('fragments are dropped', () {
      expect(
        BookmarkUrl.normalize('https://a.github.io/pitak/#top'),
        canonical,
      );
      expect(BookmarkUrl.normalize('https://a.github.io/pitak#x'), canonical);
    });

    test('a trailing index.html names the same site root', () {
      expect(
        BookmarkUrl.normalize('https://a.github.io/pitak/index.html'),
        canonical,
      );
      expect(
        BookmarkUrl.normalize('https://a.github.io/index.html'),
        'https://a.github.io/',
      );
    });

    test('repeated trailing slashes collapse to one', () {
      expect(BookmarkUrl.normalize('https://a.github.io/pitak//'), canonical);
      expect(
        BookmarkUrl.normalize('https://a.github.io//'),
        'https://a.github.io/',
      );
    });

    test('the default https port is folded away', () {
      expect(
        BookmarkUrl.normalize('https://a.github.io:443/pitak/'),
        canonical,
      );
    });

    test('every spelling resolves library.json INSIDE the site (§5.6)', () {
      for (final spelling in [
        'https://a.github.io/pitak',
        'https://a.github.io/pitak/',
        'https://A.github.io/pitak?x=1',
        'https://a.github.io/pitak/index.html',
      ]) {
        final site = BookmarkUrl.normalize(spelling)!;
        expect(
          Uri.parse(site).resolve('library.json').toString(),
          'https://a.github.io/pitak/library.json',
          reason: spelling,
        );
      }
    });
  });

  group('BookmarkUrl.normalize — rejected', () {
    const bad = [
      '', // blank
      'http://myname.github.io/', // not https
      'https://example.com/', // custom domain
      'https://github.io.evil.com/', // suffix-spoofing
      'https://evilgithub.io.attacker.net/',
      'https://pages.dev.evil.com/',
      'ftp://x.github.io/',
      'https://user:pass@x.github.io/', // credentials
      'https://user@x.github.io/', // userinfo without a password
      'https://x.pages.dev.attacker.com/',
      'https://x.github.io:8443/', // explicit non-default port
      'notaurl',
      'https://', // no host
      'javascript:alert(1)',
    ];
    for (final url in bad) {
      test('rejects "$url"', () {
        expect(BookmarkUrl.normalize(url), isNull);
        expect(BookmarkUrl.isValid(url), isFalse);
      });
    }

    test('null is rejected', () {
      expect(BookmarkUrl.normalize(null), isNull);
    });

    test('a subdomain of github.io is allowed but not a lookalike', () {
      expect(BookmarkUrl.isValid('https://a.b.github.io/'), isTrue);
      expect(BookmarkUrl.isValid('https://github.io.co/'), isFalse);
    });

    test('SECURITY: a URL longer than the §6 bound is rejected', () {
      // §6: ≤ 2048 chars. The bound itself is enforced by Uri parsing + the
      // callers' caps; a pathological over-long URL must never normalize.
      final long = 'https://x.github.io/${'a' * 4096}';
      expect(long.length, greaterThan(2048));
      expect(BookmarkUrl.normalize(long), isNull);
    });
  });

  group('BookmarkUrl.sanitize — allow-list only, verbatim (the fetcher)', () {
    test('returns an allowed URL exactly as given (trimmed)', () {
      const file = 'https://a.github.io/pitak/library.json';
      expect(BookmarkUrl.sanitize(file), file);
      expect(BookmarkUrl.sanitize('  $file  '), file);
    });

    test('does NOT canonicalize: a redirect target keeps its shape', () {
      // The fetcher re-validates every redirect Location with sanitize(); if
      // it rewrote the address, a hop to `…/library.json` would be fetched
      // as `…/library.json/` and 404.
      const hop = 'https://A.github.io/pitak/library.json?v=2';
      expect(BookmarkUrl.sanitize(hop), hop);
    });

    test('applies the SAME allow-list as normalize', () {
      for (final url in [
        'http://a.github.io/x/',
        'https://example.com/x/',
        'https://user@a.github.io/',
        'https://a.github.io:8443/',
        '',
        null,
      ]) {
        expect(BookmarkUrl.sanitize(url), isNull, reason: '$url');
      }
      expect(BookmarkUrl.sanitize('https://x.github.io/${'a' * 4096}'), isNull);
    });
  });
}
