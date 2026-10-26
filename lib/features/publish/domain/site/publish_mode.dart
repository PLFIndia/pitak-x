/// How complete a publish must be (publish domain, pure Dart; Cloudflare
/// plan R2).
///
/// Two modes, one promise each:
///  - `incremental` — an ordinary catalogue/events update. An unreadable
///    local poster or cover may fall back to the copy already published on the
///    SAME target (the historical, explicit fallback rule); it may never
///    silently drop a referenced file.
///  - `complete` — a move, a whole-site replacement or a retirement. EVERY
///    required file must have real bytes available from a local source (or a
///    verified old site), because the destination is about to replace a site
///    wholesale. A missing byte is a typed failure BEFORE any write.
library;

/// Whether a publish may reuse published bytes or must prove every file.
enum PublishMode {
  /// Ordinary catalogue/events publish: reuse unchanged published files.
  incremental,

  /// Move / replacement / retirement: a strict complete snapshot.
  complete,
}
