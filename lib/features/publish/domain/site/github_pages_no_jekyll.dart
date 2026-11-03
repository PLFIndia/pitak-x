/// `.nojekyll`: the empty file that tells GitHub Pages not to run its site
/// generator over a Pitak site (publish domain, pure Dart; plan SP5).
///
/// Why (beginner note): GitHub Pages builds every commit before it serves
/// it. Unless the site's root holds a file called `.nojekyll`, that build
/// first downloads the "Jekyll" site generator and runs it over every file.
/// A Pitak site needs none of that — it is finished files (`index.html`,
/// JSON, pictures) with no Jekyll templates — so Jekyll only copies them
/// unchanged, and its download is the slowest step of the build. Measured on
/// real Pages builds (plan S14, Appendix A): the median build was 23 %
/// shorter for a 10-cover site and 17 % for a 1,000-cover one (the plan's
/// bar was 15 %), and every Pitak file was served byte-for-byte the same
/// with and without Jekyll.
///
/// GitHub only. Cloudflare serves the uploaded files as they are, and its
/// upload rules have no content type for a file without an extension, so the
/// catalogue writes this file only for a GitHub Pages target
/// (`CatalogueInputs.gitHubPagesSite`). The catalogue section owns it
/// (`SiteSectionOwnership`), so a move away from GitHub deletes it with the
/// rest of the site.
library;

/// The `.nojekyll` file: its path at the site root and its (empty) content.
abstract final class GitHubPagesNoJekyll {
  /// The site-root path GitHub Pages looks for.
  static const String path = '.nojekyll';

  /// The file is empty: only its presence matters.
  static const List<int> bytes = <int>[];
}
