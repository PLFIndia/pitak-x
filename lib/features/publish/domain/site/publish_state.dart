/// How far a recorded publication has been proven (publish domain, pure Dart;
/// Cloudflare plan R5).
///
/// Shared by BOTH hosts on purpose (beginner note): "the API accepted it" and
/// "the live site serves it" are different facts on GitHub (a commit) and on
/// Cloudflare (a deploy), but the three states mean the same thing on each, and
/// the journal, the marker classifier and the UI copy all reason about them.
/// Two enums would be two vocabularies for one idea — exactly the drift P5
/// forbids.
library;

/// The proof level of a recorded publication.
enum PublishState {
  /// The host accepted the write (commit or deploy) but this phone has not
  /// seen the result served publicly yet.
  deployed,

  /// The live site was proven to serve what the record describes.
  live,

  /// The site now serves a moved page and nothing else.
  retired,
}
