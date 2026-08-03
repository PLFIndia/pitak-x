/// Builds the published viewer HTML from the bundled template (infra, #32).
///
/// Loads `assets/publish/index.html` and substitutes the three placeholders the
/// orchestrator's `ViewerHtmlBuilder` contract expects: library name, an inline
/// logo data URL (optional), and the contact line HTML. The library name and
/// contact values are HTML-escaped; the contact line is built by the pure
/// [PublishContactLinks] (which escapes its own parts).
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';

/// Assembles the viewer HTML bytes for upload.
final class ViewerHtmlBuilder {
  /// Creates the builder.
  const ViewerHtmlBuilder({
    required this.libraryName,
    required this.contact,
    this.logoDataUrl = '',
  });

  /// Display name shown as the page title/header.
  final String libraryName;

  /// Optional inline logo as a `data:` URL ('' = none).
  final String logoDataUrl;

  /// Optional public contact triple.
  final PublishContact contact;

  /// Loads the template and returns the substituted HTML bytes.
  Future<List<int>> build() async {
    final template = await rootBundle.loadString('assets/publish/index.html');
    final contactHtml = PublishContactLinks.render(contact, escape: _esc);
    final html = template
        .replaceAll('{{LIBRARY_NAME}}', _esc(_nonBlank(libraryName)))
        .replaceAll('{{LOGO_DATA_URL}}', _esc(_safeLogoDataUrl(logoDataUrl)))
        .replaceAll('{{CONTACT_HTML}}', contactHtml);
    return utf8.encode(html);
  }

  static String _nonBlank(String s) => s.trim().isEmpty ? 'My Library' : s;

  /// The only shape ever allowed inside the template's `<img src="...">`.
  /// SVG is deliberately excluded: an SVG document can carry script, and
  /// raster formats cover every logo the app produces.
  static final RegExp _logoDataUrlPattern = RegExp(
    r'^data:image/(?:png|jpe?g|webp|gif);base64,[A-Za-z0-9+/=]+$',
  );

  /// Constrains [value] to the strict `data:image/...;base64,` shape before
  /// it lands inside an `<img src="...">` attribute (REVIEW_FINDINGS_2 S7):
  /// the placeholder is substituted raw, so an unconstrained value is an
  /// attribute-injection sink for whoever wires the user-logo feature to it.
  /// FAIL CLOSED: anything else becomes '' — the template's `onerror` hides
  /// the empty img. (The result is also HTML-escaped at the call site as
  /// defense in depth; escaping is a no-op on a validated base64 value.)
  static String _safeLogoDataUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    return _logoDataUrlPattern.hasMatch(v) ? v : '';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
