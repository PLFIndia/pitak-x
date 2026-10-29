/// Where a Pitak Worker serves each uploaded asset (public read-back only).
///
/// Every Pitak deployment uses `html_handling: auto-trailing-slash`
/// (`CloudflareDeploymentKind.htmlHandling` reads [CloudflareHtmlRouting.
/// htmlHandling], so the deployed setting and this rule cannot drift apart).
/// With that setting Cloudflare
/// does NOT serve an HTML asset at its file name; it answers with a 307 to
/// the canonical address instead (documented in "HTML handling", Workers
/// static assets, and observed in S2/T8a and the S11 J.7 smoke):
///
/// | Asset            | Served (200) at | Its file name answers |
/// |------------------|-----------------|-----------------------|
/// | `index.html`     | `/`             | 307 → `/`             |
/// | `events.html`    | `/events`       | 307 → `/events`       |
/// | `dir/page.html`  | `/dir/page`     | 307 → `/dir/page`     |
/// | `books.json`     | `/books.json`   | (not HTML: unchanged) |
///
/// Read-back refuses every redirect on purpose (R16), so verification must
/// request the canonical address directly. This is NOT a second path policy
/// and does not "fix up" what gets published: [SitePath] still decides which
/// files exist, and the same asset is uploaded under its own name. This only
/// answers "which public URL returns these exact bytes?".
library;

import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// The `auto-trailing-slash` routing rule for read-back URLs.
abstract final class CloudflareHtmlRouting {
  /// The `html_handling` value every deployment sends, and the only one
  /// [servedPath] describes. Changing it means rewriting [servedPath].
  static const String htmlHandling = 'auto-trailing-slash';

  static const String _html = '.html';
  static const String _index = 'index.html';

  /// The site-relative path that serves [assetPath] with a 200, where `''`
  /// means the site root. Returns null when there is no address the bounded
  /// read-back may request: an invalid path, or a nested `dir/index.html`,
  /// whose canonical `dir/` form has an empty segment the read-back URL
  /// policy refuses. No Pitak site publishes nested HTML; null makes such a
  /// file unverifiable (fail closed) rather than guessed.
  static String? servedPath(String assetPath) {
    if (SitePath.tryParse(assetPath) == null) return null;
    if (!assetPath.endsWith(_html)) return assetPath;
    if (assetPath == _index) return '';
    if (assetPath.endsWith('/$_index')) return null;
    final stem = assetPath.substring(0, assetPath.length - _html.length);
    // `.html` alone or `dir/.html` has no name for Cloudflare to route.
    if (stem.isEmpty || stem.endsWith('/')) return null;
    return stem;
  }
}
