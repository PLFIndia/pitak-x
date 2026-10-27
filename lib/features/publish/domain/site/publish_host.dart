/// Which host a library publishes to (publish domain, pure Dart; Cloudflare
/// plan M2/E.1).
///
/// One active host at a time: GitHub Pages or Cloudflare Workers. The value is
/// part of the sealed `PublishTarget`'s identity, so "which host" can never be
/// inferred from a URL string — it comes from the type of target an operation
/// was given.
library;

/// The publishing hosts the app supports.
enum PublishHost {
  /// GitHub Pages on a branch of the user's repository.
  github,

  /// A dedicated Cloudflare Worker serving static assets.
  cloudflare,
}
