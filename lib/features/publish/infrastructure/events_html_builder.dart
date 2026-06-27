/// Builds the published events page HTML from the bundled template (#events).
///
/// Mirrors `ViewerHtmlBuilder`: loads `assets/publish/events.html` and
/// substitutes the library name + the pre-rendered poster markup. Both dynamic
/// values are HTML-escaped (the poster renderer escapes its own parts).
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pitaka/features/publish/domain/events_posters_html.dart';

/// Assembles the events page HTML bytes for upload.
final class EventsHtmlBuilder {
  /// Creates the builder.
  const EventsHtmlBuilder({required this.libraryName, required this.posters});

  /// Display name shown in the title/header.
  final String libraryName;

  /// The posters to bake into the page (already redacted to path + caption).
  final List<PublishPoster> posters;

  /// Loads the template and returns the substituted HTML bytes.
  Future<List<int>> build() async {
    final template = await rootBundle.loadString('assets/publish/events.html');
    final postersHtml = EventsPostersHtml.render(posters, escape: _esc);
    final html = template
        .replaceAll('{{LIBRARY_NAME}}', _esc(_nonBlank(libraryName)))
        .replaceAll('{{POSTERS_HTML}}', postersHtml);
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
