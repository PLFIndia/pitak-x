/// Pure poster-markup renderer for the published events page (domain, #events).
///
/// Turns the publish-facing poster list into the inner HTML baked into
/// `events.html` at publish time. Pure + injectable escape (like
/// `PublishContactLinks`), unit-testable without the asset bundle.
///
/// Image paths are repo-relative (`posters/<id>.jpg`, same-origin under the
/// page CSP `img-src 'self'`); descriptions are user text and MUST be escaped.
library;

/// One poster as it will appear on the published page.
final class PublishPoster {
  /// Creates a publish poster from a repo-relative [imagePath] + [description].
  const PublishPoster({required this.imagePath, this.description = ''});

  /// Repo-relative image path, e.g. `posters/ab12.jpg`.
  final String imagePath;

  /// Optional caption (may be empty).
  final String description;
}

/// Renders the `<main>` poster section for the events page.
abstract final class EventsPostersHtml {
  /// Builds the posters HTML for [posters], escaping every dynamic value with
  /// [escape]. Returns an empty-state block when [posters] is empty.
  static String render(
    List<PublishPoster> posters, {
    required String Function(String) escape,
  }) {
    if (posters.isEmpty) {
      return '<p class="empty">No events right now. Check back soon.</p>';
    }
    final figures = posters.map((p) => _figure(p, escape)).join('\n');
    return '<div class="posters">\n$figures\n</div>';
  }

  static String _figure(PublishPoster p, String Function(String) escape) {
    final src = escape(p.imagePath);
    final hasDesc = p.description.trim().isNotEmpty;
    final desc = hasDesc
        ? '<div class="desc">${escape(p.description.trim())}</div>'
        : '<div class="desc empty">No description.</div>';
    final img = '<img src="$src" alt="Event poster" loading="lazy" />';
    return '<figure class="poster">$img$desc</figure>';
  }
}
