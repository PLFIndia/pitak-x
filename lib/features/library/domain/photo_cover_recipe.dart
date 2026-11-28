/// How Pitak stores a cover that the user photographs with the camera
/// (library domain, pure Dart; maintainer decision of 2026-11-10).
///
/// Why a cover photo is this small (beginner note): a cover only has to give
/// an impression of what the face of the actual item looks like. It must be
/// readable; picture quality beyond that adds nothing. A smaller file also
/// means that a library with thousands of covers still fits into one backup.
///
/// Why the numbers live in one named place: two controllers store a captured
/// cover (`BookCoverController` for an item that exists, `FormCoverController`
/// for a form that is not saved yet). If each carried its own numbers, they
/// could drift apart, and a cover would come out differently depending on the
/// screen it was taken from.
///
/// What this recipe does NOT apply to:
///  - covers already stored on the phone: they are never re-encoded (a stored
///    cover file never changes, ADR 0020 Decision 1);
///  - covers downloaded for an ISBN, and the library logo: both keep the
///    shared default of `ImageDownscaler` (400 × 600 at quality 80);
///  - the publish step, which keeps its own recipe (`PublishCoverRendition`,
///    400 × 600 at quality 80). That step never enlarges a picture, so a cover
///    made with this recipe reaches the website at the size it was stored.
///    The publish recipe itself is unchanged, so no new
///    `PublishCoverRendition.current` is needed.
library;

/// The size limit and JPEG quality of a photographed cover.
abstract final class PhotoCoverRecipe {
  /// The stored picture fits within this width (pixels). The aspect ratio is
  /// kept and a smaller picture is never enlarged.
  static const int maxWidth = 240;

  /// The stored picture fits within this height (pixels).
  static const int maxHeight = 360;

  /// JPEG quality of the stored file (0 to 100).
  static const int jpegQuality = 70;
}
