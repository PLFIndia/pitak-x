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
        .replaceAll('{{LOGO_DATA_URL}}', logoDataUrl)
        .replaceAll('{{CONTACT_HTML}}', contactHtml);
    return utf8.encode(html);
  }

  static String _nonBlank(String s) => s.trim().isEmpty ? 'My Library' : s;

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
