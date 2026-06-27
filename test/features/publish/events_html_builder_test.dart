import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/infrastructure/events_html_builder.dart';

void main() {
  // Loads a bundled asset via rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('substitutes the library name (escaped) and poster markup', () async {
    final bytes = await const EventsHtmlBuilder(
      libraryName: 'Ravi & <Co>',
      posters: [
        PublishPoster(imagePath: 'posters/a.jpg', description: 'Story hour'),
      ],
    ).build();
    final html = utf8.decode(bytes);

    expect(html, isNot(contains('{{LIBRARY_NAME}}')));
    expect(html, isNot(contains('{{POSTERS_HTML}}')));
    expect(html, contains('Ravi &amp; &lt;Co&gt;'));
    expect(html, contains('src="posters/a.jpg"'));
    expect(html, contains('Story hour'));
    // CSP is the strict same-origin variant (no cover CDNs on this page).
    expect(html, contains("img-src 'self' data:"));
  });

  test('blank library name falls back to a default', () async {
    final html = utf8.decode(
      await const EventsHtmlBuilder(libraryName: '', posters: []).build(),
    );
    expect(html, contains('My Library'));
    // No posters → empty-state copy.
    expect(html, contains('No events'));
  });
}
