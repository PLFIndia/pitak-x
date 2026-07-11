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
}
