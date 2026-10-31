import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// SPECIFICATION of the one publish path policy (Cloudflare plan R23, J.1).
///
/// The point of these tests: a path either names a file INSIDE the site or it
/// is refused. Nothing here is "fixed up", because a repaired path is a
/// different file than the builder asked for — and an escaping path is
/// somebody else's file.
void main() {
  group('SitePath accepts exactly the site-relative charset', () {
    for (final valid in <String>[
      'books.json',
      'index.html',
      '404.html',
      'pitak-publish.json',
      'covers/0123456789abcdef0123456789abcdef01234567.jpg',
      'posters/a.jpg',
      'a/b/c/d.json',
      'A-Z_09.a-b_c',
      'x.y.z',
    ]) {
      test('"$valid" is a valid path and is returned unchanged', () {
        final path = SitePath.tryParse(valid);

        expect(path, isNotNull);
        expect(path!.value, valid);
        expect(path.toString(), valid);
      });
    }

    test('the length cap is inclusive and one over it is refused', () {
      final atLimit = 'a' * SitePath.maxLength;
      final overLimit = 'a' * (SitePath.maxLength + 1);

      expect(SitePath.isValid(atLimit), isTrue);
      expect(SitePath.isValid(overLimit), isFalse);
    });
  });

  group('SitePath refuses everything that could leave the site root', () {
    for (final hostile in <String?>[
      '',
      // Absolute and Windows separators.
      '/books.json',
      '//books.json',
      r'covers\a.jpg',
      // Traversal, in every spelling the charset could permit.
      '..',
      '.',
      '../books.json',
      'covers/../../etc/passwd',
      'a/./b',
      'a//b',
      'a/',
      'a/..',
      // Encoded separators are refused because `%` is not in the charset.
      'covers/%2e%2e/x.jpg',
      'a%2Fb',
      '%2Fetc%2Fpasswd',
      // Whitespace, control characters, NUL and a trailing dot are not paths.
      ' books.json',
      'books.json ',
      'books json',
      'books\tjson',
      'books\njson',
      'books\u0000json',
      'books\u007fjson',
      // Non-ASCII (an internationalized file name is not a publish path).
      'böcker.json',
      '本.json',
      // URL syntax is not a path.
      'https://evil.example/x',
      'a?b',
      'a#b',
      'a:b',
      '~/x',
      null,
    ]) {
      test('"$hostile" is refused', () {
        expect(SitePath.tryParse(hostile), isNull);
        expect(SitePath.isValid(hostile), isFalse);
      });
    }
  });

  group('extension', () {
    test('is the text after the last dot of the LAST segment', () {
      expect(SitePath.tryParse('books.json')!.extension, 'json');
      expect(SitePath.tryParse('covers/a.b.jpg')!.extension, 'jpg');
      // Case is preserved: the caller decides what a case-variant means.
      expect(SitePath.tryParse('x.JPG')!.extension, 'JPG');
    });

    test('is null when there is no usable extension', () {
      expect(SitePath.tryParse('README')!.extension, isNull);
      expect(SitePath.tryParse('.gitignore')!.extension, isNull);
      expect(SitePath.tryParse('trailing.')!.extension, isNull);
      expect(SitePath.tryParse('a/b')!.extension, isNull);
    });
  });

  group('the two older path checks now delegate here', () {
    test('isSafePublishPath is the shared policy', () {
      expect(isSafePublishPath('books.json'), isTrue);
      expect(isSafePublishPath('../books.json'), isFalse);
      expect(isSafePublishPath('a%2Fb'), isFalse);
    });

    test('section ownership uses the shared policy for every host', () {
      expect(SiteSection.catalogue.owns('books.json'), isTrue);
      expect(SiteSection.catalogue.owns('../books.json'), isFalse);
      expect(SiteSection.events.owns('posters/a b.jpg'), isFalse);
      expect(SiteSection.retirement.owns('pitak-publish.json'), isTrue);
    });

    test('githubPagesFileUrl keeps every valid GitHub URL byte-identical', () {
      expect(
        githubPagesFileUrl('owner/repo', 'events.html'),
        'https://owner.github.io/repo/events.html',
      );
      expect(
        githubPagesFileUrl('owner/repo', 'covers/x.jpg'),
        'https://owner.github.io/repo/covers/x.jpg',
      );
      for (final refused in <String>['', '/x', '../x', 'a/../b', 'a b']) {
        expect(githubPagesFileUrl('owner/repo', refused), isNull);
      }
    });
  });
}
