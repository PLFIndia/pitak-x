import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// The allow-list cases carried over verbatim from the deleted bookmarks
/// feature (`test/features/bookmarks/library_bookmark_test.dart`, ADR 0012):
/// `BookmarkUrl` moved to the network domain unchanged, and these are the
/// security boundary for every saved/scanned/fetched site URL (§6).
void main() {
  group('BookmarkUrl.normalize — accepted', () {
    const ok = [
      'https://myname.github.io/library/',
      'https://myname.github.io',
      'https://github.io', // bare apex
      'https://lib.pages.dev/',
      'https://my-library.pages.dev/catalogue',
      'https://pages.dev',
    ];
    for (final url in ok) {
      test('accepts $url', () {
        expect(BookmarkUrl.normalize(url), url);
        expect(BookmarkUrl.isValid(url), isTrue);
      });
    }

    test('trims surrounding whitespace', () {
      expect(
        BookmarkUrl.normalize('  https://x.github.io/  '),
        'https://x.github.io/',
      );
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
      'https://x.pages.dev.attacker.com/',
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
}
