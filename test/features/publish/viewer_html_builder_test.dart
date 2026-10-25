import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

void main() {
  // The builder reads a bundled asset via rootBundle, so the binding must be
  // initialized and the asset available to the test bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('substitutes library name + contact, escapes HTML', () async {
    final bytes = await const ViewerHtmlBuilder(
      libraryName: 'Ravi & Co <Books>',
      sharing: LocationSharing.exact,
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

  // Regression for REVIEW_FINDINGS_2 S7: the logo placeholder substitutes
  // into an <img src="..."> attribute, so only a strict data:image base64
  // shape may pass — anything else must be dropped (fail closed).
  group('logo data URL validation', () {
    test('a valid raster data URL passes through', () async {
      const logo = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==';
      final html = utf8.decode(
        await const ViewerHtmlBuilder(
          libraryName: 'X',
          sharing: LocationSharing.exact,
          contact: PublishContact(),
          logoDataUrl: logo,
        ).build(),
      );
      expect(html, contains('src="$logo"'));
    });

    test('attribute-injection attempts are dropped', () async {
      final html = utf8.decode(
        await const ViewerHtmlBuilder(
          libraryName: 'X',
          sharing: LocationSharing.exact,
          contact: PublishContact(),
          logoDataUrl: 'x" onerror="alert(1)',
        ).build(),
      );
      expect(html, isNot(contains('onerror="alert')));
      expect(html, contains('src=""'));
    });

    test('svg data URLs and non-data schemes are dropped', () async {
      for (final bad in [
        'data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=',
        'javascript:alert(1)',
        'https://evil.example/x.png',
        'data:text/html;base64,PHNjcmlwdD4=',
      ]) {
        final html = utf8.decode(
          await ViewerHtmlBuilder(
            libraryName: 'X',
            sharing: LocationSharing.exact,
            contact: const PublishContact(),
            logoDataUrl: bad,
          ).build(),
        );
        expect(html, isNot(contains(bad)), reason: 'must drop: $bad');
      }
    });
  });

  test('blank library name falls back to a default', () async {
    final html = utf8.decode(
      await const ViewerHtmlBuilder(
        libraryName: '',
        sharing: LocationSharing.exact,
        contact: PublishContact(),
      ).build(),
    );
    expect(html, contains('My Library'));
  });

  test('carries the events banner + a same-origin events.html probe', () async {
    final html = utf8.decode(
      await const ViewerHtmlBuilder(
        libraryName: 'X',
        sharing: LocationSharing.exact,
        contact: PublishContact(),
      ).build(),
    );
    // Banner element links to the events page and starts hidden (revealed by
    // the probe only when events.html exists).
    expect(html, contains('id="eventsBanner"'));
    expect(html, contains('href="events.html"'));
    expect(html, contains('class="events-banner"'));
    // The reveal probe is a HEAD fetch of the sibling page.
    expect(html, contains('fetch("events.html"'));
  });

  test(
    'carries the v7 kind facet, series grouping and kind badges (W3)',
    () async {
      final html = utf8.decode(
        await const ViewerHtmlBuilder(
          libraryName: 'X',
          sharing: LocationSharing.exact,
          contact: PublishContact(),
        ).build(),
      );
      // Fixed kind facet (kinds are app-defined, ADR 0013 F3).
      expect(html, contains('id="kind"'));
      expect(
        html,
        contains('<option value="magazine-issue">Magazines</option>'),
      );
      // The additive payload keys are read defensively (older payloads lack
      // them, older viewers ignore them).
      expect(html, contains('data.periodicals'));
      expect(html, contains('(b.kind || "book")'));
      // Issues group under their series; bound volumes get the badge.
      expect(html, contains('function groupIssues('));
      expect(html, contains('seriesLabel'));
      expect(html, contains('>Bound volume</span>'));
    },
  );
}
