import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';

void main() {
  test('derives the Pages URL from owner/repo', () {
    expect(
      githubPagesUrlFor('booklover/my-library'),
      'https://booklover.github.io/my-library/',
    );
  });

  test('returns null for null, malformed, or empty parts', () {
    expect(githubPagesUrlFor(null), isNull);
    expect(githubPagesUrlFor(''), isNull);
    expect(githubPagesUrlFor('no-slash'), isNull);
    expect(githubPagesUrlFor('a/b/c'), isNull);
    expect(githubPagesUrlFor('/repo'), isNull);
    expect(githubPagesUrlFor('owner/'), isNull);
  });

  group('N09 — one resolver for every published address', () {
    test('a user site (owner/owner.github.io) is served at the account root, '
        'not under a /owner.github.io/ folder', () {
      expect(
        githubPagesUrlFor('booklover/booklover.github.io'),
        'https://booklover.github.io/',
      );
    });

    test('the user-site rule is case-insensitive (GitHub logins are)', () {
      expect(
        githubPagesUrlFor('BookLover/booklover.github.io'),
        'https://booklover.github.io/',
      );
      expect(
        githubPagesUrlFor('booklover/BookLover.GitHub.io'),
        'https://booklover.github.io/',
      );
    });

    test('the site host is lower-cased (DNS is case-insensitive)', () {
      expect(
        githubPagesUrlFor('BookLover/my-library'),
        'https://booklover.github.io/my-library/',
      );
    });

    test('a repo that merely CONTAINS github.io is a project site', () {
      expect(
        githubPagesUrlFor('booklover/other.github.io'),
        'https://booklover.github.io/other.github.io/',
      );
    });

    test('githubPagesFileUrl appends a relative file path to the site', () {
      expect(
        githubPagesFileUrl('booklover/my-library', 'events.html'),
        'https://booklover.github.io/my-library/events.html',
      );
      expect(
        githubPagesFileUrl('booklover/booklover.github.io', 'events.html'),
        'https://booklover.github.io/events.html',
      );
    });

    test('githubPagesFileUrl refuses what the site resolver refuses', () {
      expect(githubPagesFileUrl(null, 'events.html'), isNull);
      expect(githubPagesFileUrl('owner/', 'events.html'), isNull);
    });

    test('githubPagesFileUrl refuses an absolute or escaping path', () {
      expect(githubPagesFileUrl('o/r', '/events.html'), isNull);
      expect(githubPagesFileUrl('o/r', '../events.html'), isNull);
      expect(githubPagesFileUrl('o/r', 'a/../b.html'), isNull);
      expect(githubPagesFileUrl('o/r', ''), isNull);
      expect(githubPagesFileUrl('o/r', 'https://evil.example/x'), isNull);
    });

    test("owner and repo names outside GitHub's charset are refused", () {
      // A stored target is validated before it is written, but the resolver
      // is the last line before a URL is shown/shared — refuse anyway.
      expect(githubPagesUrlFor('own er/repo'), isNull);
      expect(githubPagesUrlFor('owner/re po'), isNull);
      expect(githubPagesUrlFor('owner/repo?x=1'), isNull);
      expect(githubPagesUrlFor('evil.example/repo'), isNull);
    });
  });
}
