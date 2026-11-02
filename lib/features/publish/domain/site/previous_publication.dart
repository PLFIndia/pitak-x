/// What a builder may know about the site that is already published
/// (publish domain, pure Dart; Cloudflare plan E.1/R2/R5).
///
/// Why an interface instead of passing the manifest around (beginner note):
/// the catalogue/events section builders are HOST-NEUTRAL — the GitHub and the
/// Cloudflare adapters both feed them. Each host stores different manifest
/// details (git blob shas vs asset hashes), but both need the same
/// questions answered:
///  - "which content sha is already live at this path?" (skip an unchanged
///    upload),
///  - "which cover SOURCE did the last publish use for this key?", and
///  - "were those covers made with the rendition this build makes?" — the
///    last two together let a cover that is already online be reused without
///    reading or re-encoding it (ADR 0020, plan CV2).
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

  /// The cover rendition (`PublishCoverRendition`) of the covers this record
  /// holds, or null when it cannot vouch for reusing them without their
  /// bytes (ADR 0020 Decision 3).
  ///
  /// A cover is published by reference — not read, not re-encoded — only
  /// when this equals `PublishCoverRendition.current`, the record names the
  /// same source for its key, and the record holds its path (plan CV2).
  /// Null (a record written before ADR 0020, another target, a record whose
  /// hashes this build cannot use, or one whose cover files changed under
  /// it) makes every cover be produced again, which is always safe.
  int? get reusableCoverRendition;

  /// True when the recorded `books.json` carries item keys THIS phone wrote
  /// (ADR 0019 Decision 7b), so a recorded `availability.json` names the
  /// items readers see.
  ///
  /// A publish that cannot write a fresh `availability.json` (the vault is
  /// locked, or it builds no catalogue) keeps a recorded one only while this
  /// is true. Otherwise its keys may name other items — after a restore of
  /// another library (plan J9), or after another writer replaced
  /// `books.json` — so the file is deleted instead (plan S6).
  bool get catalogueKeyed;
}
