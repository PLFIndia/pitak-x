import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

void main() {
  group('CoverUrlAllowList.sanitize', () {
    test('allows a local covers/ path', () {
      expect(CoverUrlAllowList.sanitize('covers/3f2c.jpg'), 'covers/3f2c.jpg');
    });

    test('rejects covers/ traversal and nesting', () {
      expect(CoverUrlAllowList.sanitize('covers/../secret'), isNull);
      expect(CoverUrlAllowList.sanitize('covers/sub/x.jpg'), isNull);
      expect(CoverUrlAllowList.sanitize('covers/'), isNull);
    });

    test('allows https on allow-listed hosts', () {
      expect(
        CoverUrlAllowList.sanitize(
          'https://covers.openlibrary.org/b/id/1-M.jpg',
        ),
        isNotNull,
      );
      expect(
        CoverUrlAllowList.sanitize('https://books.google.com/x.jpg'),
        isNotNull,
      );
    });

    test('rejects non-allow-listed hosts and schemes', () {
      expect(
        CoverUrlAllowList.sanitize('https://attacker.example/t.jpg'),
        isNull,
      );
      expect(
        CoverUrlAllowList.sanitize('http://covers.openlibrary.org/x'),
        isNull,
      );
      expect(CoverUrlAllowList.sanitize('data:image/png;base64,AAAA'), isNull);
      expect(CoverUrlAllowList.sanitize('javascript:alert(1)'), isNull);
    });

    test('rejects userinfo auth-confusion', () {
      expect(
        CoverUrlAllowList.sanitize(
          'https://covers.openlibrary.org@attacker.example/x',
        ),
        isNull,
      );
    });

    test('blank/null → null', () {
      expect(CoverUrlAllowList.sanitize(null), isNull);
      expect(CoverUrlAllowList.sanitize('   '), isNull);
    });
  });

  // M09: the display/materialise path needs "is this a FETCHABLE remote
  // cover?" — the https branch of sanitize only, never a local path.
  group('CoverUrlAllowList.remoteHttpsOf', () {
    test('returns the trimmed URL for an allow-listed https host', () {
      expect(
        CoverUrlAllowList.remoteHttpsOf(
          '  https://covers.openlibrary.org/b/id/1-L.jpg ',
        ),
        'https://covers.openlibrary.org/b/id/1-L.jpg',
      );
      expect(
        CoverUrlAllowList.remoteHttpsOf(
          'https://BOOKS.GOOGLE.COM/books/content?id=x',
        ),
        isNotNull,
        reason: 'host match is case-insensitive',
      );
    });

    test('rejects local refs even though sanitize allows them', () {
      expect(CoverUrlAllowList.remoteHttpsOf('covers/abc.jpg'), isNull);
      expect(
        CoverUrlAllowList.remoteHttpsOf('file:///x/covers/abc.jpg'),
        isNull,
      );
    });

    test('rejects non-allow-listed hosts, subdomains, http, userinfo', () {
      expect(
        CoverUrlAllowList.remoteHttpsOf('https://example.com/c.jpg'),
        isNull,
      );
      expect(
        CoverUrlAllowList.remoteHttpsOf(
          'https://evil.covers.openlibrary.org/c',
        ),
        isNull,
      );
      expect(
        CoverUrlAllowList.remoteHttpsOf(
          'http://covers.openlibrary.org/b/id/1-L.jpg',
        ),
        isNull,
      );
      expect(
        CoverUrlAllowList.remoteHttpsOf(
          'https://covers.openlibrary.org@evil.com/c.jpg',
        ),
        isNull,
      );
      expect(CoverUrlAllowList.remoteHttpsOf(null), isNull);
      expect(CoverUrlAllowList.remoteHttpsOf(''), isNull);
    });
  });
}
