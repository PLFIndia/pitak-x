/// How Pitak turns a cover picture into the file it publishes (publish
/// domain, pure Dart; ADR 0020 Decision 3, plan CV3).
///
/// Why a numbered "rendition" (beginner note): from ADR 0020 on, a publish
/// skips a cover that is already online in exactly the form this app would
/// produce again (plan CV2), instead of re-reading and re-encoding it every
/// time. That is only correct while the recipe stays the same. So the recipe
/// gets a number, both publish records store the number their covers were
/// made with, and a cover is reused only when the stored number equals
/// [PublishCoverRendition.current].
///
/// The recipe itself is `ImageDownscaler` with its default parameters (core),
/// which both publish readers call: the local cover reader and the bounded
/// remote-cover download. The constants below describe those defaults, and
/// `publish_cover_rendition_test.dart` pins them to each other.
///
/// Changing the recipe ON PURPOSE (a new size, a new JPEG quality, a new
/// resize or metadata rule in `ImageDownscaler`) therefore means: change the
/// constants below AND add one to [PublishCoverRendition.current]. The next
/// publish then renders every cover once, visibly and deliberately, instead
/// of either never updating old covers or silently re-uploading all of them.
/// The test fails when the parameters change but the number does not.
///
/// What does NOT need a new number: an `image` package update that encodes
/// the same picture into slightly different bytes. The old file still shows
/// the same picture at the same size, and avoiding a mass re-upload after an
/// app update is the point of plan Phase 2.
library;

/// The publish rendition: its number and the parameters it stands for.
abstract final class PublishCoverRendition {
  /// The rendition this build produces. Stored in both publish records as
  /// `coverRendition`; a record without it (written before ADR 0020) reads as
  /// unknown, which renders every cover once, exactly as before.
  static const int current = 1;

  /// Rendition 1: fit within this width (pixels), aspect kept, never
  /// upscaled.
  static const int maxWidth = 400;

  /// Rendition 1: fit within this height (pixels).
  static const int maxHeight = 600;

  /// Rendition 1: JPEG quality. Every rendition also strips all metadata
  /// (EXIF, GPS) and keeps frame 0 only (`ImageDownscaler.downscaleJpeg`).
  static const int jpegQuality = 80;

  /// The stored number in [raw], or null when it is missing or not a
  /// positive whole number. Null means "unknown", the safe reading: every
  /// cover is produced again.
  static int? tryParse(Object? raw) => raw is int && raw >= 1 ? raw : null;
}
