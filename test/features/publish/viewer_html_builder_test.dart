import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';

void main() {
  // The builder reads a bundled asset via rootBundle, so the binding must be
  // initialized and the asset available to the test bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('substitutes library name + contact, escapes HTML', () async {
    final bytes = await const ViewerHtmlBuilder(
      libraryName: 'Ravi & Co <Books>',
      contact: PublishContact(email: 'a@b.com'),
    ).build();
    final html = utf8.decode(bytes);

    // Placeholder gone, escaped name present.
    expect(html, isNot(contains('{{LIBRARY_NAME}}')));
    expect(html, contains('Ravi &amp; Co &lt;Books&gt;'));
    // Contact rendered.
    expect(html, isNot(contains('{{CONTACT_HTML}}')));
    expect(html, contains('mailto:a@b.com'));
    // Logo placeholder cleared when none provided.
    expect(html, isNot(contains('{{LOGO_DATA_URL}}')));
  });

  test('blank library name falls back to a default', () async {
    final html = utf8.decode(
      await const ViewerHtmlBuilder(
        libraryName: '',
        contact: PublishContact(),
      ).build(),
    );
    expect(html, contains('My Library'));
  });
}
