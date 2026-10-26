import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/domain/published_event_poster_resolver.dart';

void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  test('resolves a poster inside the saved project directory', () {
    final request = PublishedEventPosterResolver.resolve(
      site,
      '  posters/a.jpg  ',
    );
    expect(request, isA<SameSiteCoverRequest>());
    expect(request!.url, 'https://kadugodi.github.io/pitak/posters/a.jpg');
    expect(request.sanitize(request.url), request.url);
    expect(
      request.sanitize('https://kadugodi.github.io/other/posters/a.jpg'),
      isNull,
    );
    expect(request.sanitize('https://evil.example/posters/a.jpg'), isNull);
  });

  test('refuses absolute, traversal, nested and URL-smuggling references', () {
    for (final ref in [
      'https://kadugodi.github.io/pitak/posters/a.jpg',
      'posters/../secret.jpg',
      'posters/a/b.jpg',
      'posters/a.jpg?x=1',
      'posters/a.jpg#fragment',
      'posters/a%2fb.jpg',
      r'posters/a\b.jpg',
      'covers/a.jpg',
    ]) {
      expect(
        PublishedEventPosterResolver.resolve(site, ref),
        isNull,
        reason: ref,
      );
    }
  });
}
