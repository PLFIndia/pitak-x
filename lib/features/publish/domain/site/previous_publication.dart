/// What a builder may know about the site that is already published
/// (publish domain, pure Dart; Cloudflare plan E.1/R2/R5).
///
/// Why an interface instead of passing the manifest around (beginner note):
/// the catalogue/events section builders are HOST-NEUTRAL — the GitHub and the
/// Cloudflare adapters both feed them. Each host stores different manifest
/// details (git blob shas vs asset hashes), but both need the same two
/// questions answered:
///  - "which content sha is already live at this path?" (skip an unchanged
///    upload), and
///  - "which cover SOURCE URL did the last publish use for this key?" (skip a
///    remote cover whose URL did not change).
///
/// `PublishManifest` (GitHub) and the Cloudflare manifest implement this view;
/// the builders never see host-specific fields.
library;

/// Read-only view of the last successful publication on one target.
abstract interface class PreviousPublication {
  /// The content sha (host-neutral: `GitBlobSha` text) recorded for [path],
  /// or null when this phone has no record of that path.
  String? shaFor(String path);

  /// The cover source URL recorded for [key] (`<itemId>` or
  /// `periodical:<uid>`), or null when none was recorded.
  String? coverSourceFor(String key);

  /// Every app-owned path this phone recorded for the target. Used to compute
  /// EXACT deletions (never a prefix sweep — R13): a section may only delete
  /// paths it owns, and only those it really published.
  Iterable<String> get ownedPaths;
}
