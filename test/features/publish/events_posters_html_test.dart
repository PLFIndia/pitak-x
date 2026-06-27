import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';

void main() {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  test('empty posters render the empty-state block', () {
    final html = EventsPostersHtml.render(const [], escape: esc);
    expect(html, contains('class="empty"'));
    expect(html, contains('No events'));
  });

  test('a poster with a description renders an img + caption', () {
    final html = EventsPostersHtml.render(const [
      PublishPoster(imagePath: 'posters/a.jpg', description: 'Story hour'),
    ], escape: esc);
    expect(html, contains('class="posters"'));
    expect(html, contains('src="posters/a.jpg"'));
    expect(html, contains('Story hour'));
    expect(html, contains('class="desc"'));
  });

  test('a poster without a description shows the muted placeholder', () {
    final html = EventsPostersHtml.render(const [
      PublishPoster(imagePath: 'posters/b.jpg'),
    ], escape: esc);
    expect(html, contains('class="desc empty"'));
    expect(html, contains('No description.'));
  });

  test('escapes a hostile description (no raw markup leaks through)', () {
    final html = EventsPostersHtml.render(const [
      PublishPoster(
        imagePath: 'posters/c.jpg',
        description: '<script>alert(1)</script>',
      ),
    ], escape: esc);
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('renders both posters in order', () {
    final html = EventsPostersHtml.render(const [
      PublishPoster(imagePath: 'posters/a.jpg', description: 'one'),
      PublishPoster(imagePath: 'posters/b.jpg', description: 'two'),
    ], escape: esc);
    expect(
      html.indexOf('posters/a.jpg'),
      lessThan(html.indexOf('posters/b.jpg')),
    );
  });
}
