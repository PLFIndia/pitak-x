import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';

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
  });

  group('LibraryBookmark.create', () {
    test('builds with a trimmed label + normalized url', () {
      final b = LibraryBookmark.create(
        label: '  My Library  ',
        url: 'https://x.github.io/',
      );
      expect(b, isNotNull);
      expect(b!.label, 'My Library');
      expect(b.url, 'https://x.github.io/');
    });

    test('rejects a blank label', () {
      expect(
        LibraryBookmark.create(label: '   ', url: 'https://x.github.io/'),
        isNull,
      );
    });

    test('rejects an over-long label', () {
      final long = 'x' * (LibraryBookmark.maxLabelLength + 1);
      expect(
        LibraryBookmark.create(label: long, url: 'https://x.github.io/'),
        isNull,
      );
    });

    test('rejects a non-Pages url', () {
      expect(
        LibraryBookmark.create(label: 'X', url: 'https://example.com/'),
        isNull,
      );
    });
  });

  group('LibraryBookmark JSON', () {
    test('round-trips', () {
      final b = LibraryBookmark.create(
        label: 'Lib',
        url: 'https://x.pages.dev/',
      )!;
      expect(LibraryBookmark.fromJson(b.toJson())!.label, 'Lib');
      expect(LibraryBookmark.fromJson(b.toJson())!.url, 'https://x.pages.dev/');
    });

    test('fromJson re-validates and rejects a bad stored url', () {
      expect(
        LibraryBookmark.fromJson({'label': 'X', 'url': 'https://evil.com/'}),
        isNull,
      );
    });

    test('fromJson rejects malformed shapes', () {
      expect(LibraryBookmark.fromJson(null), isNull);
      expect(LibraryBookmark.fromJson('x'), isNull);
      expect(LibraryBookmark.fromJson({'label': 'only'}), isNull);
    });
  });
}
