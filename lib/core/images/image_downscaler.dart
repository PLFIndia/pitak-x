/// Cover image downscaling (core util, AGENTS.md §3.1).
///
/// Port of Kotlin `ImagePipeline.downscaleForPublish`: fit within a max
/// width×height (book aspect, default 400×600) preserving aspect ratio, then
/// re-encode as JPEG at a fixed quality (default 80). Used both for the stored
/// book cover (camera capture) and the published cover bundle, so a captured
/// photo never lands at multi-megapixel size on disk or in a git push.
///
/// Pure-Dart via the `image` package (decode/resize/encode) — no platform
/// dependency, so it is unit-testable and runs the same on every target.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Downscales + JPEG-encodes cover images to a bounded size.
abstract final class ImageDownscaler {
  /// Default max width (book cover aspect ~2:3).
  static const int maxWidth = 400;

  /// Default max height.
  static const int maxHeight = 600;

  /// Default JPEG quality.
  static const int jpegQuality = 80;

  /// Decodes [bytes], scales it to fit within [maxW]×[maxH] (aspect preserved,
  /// never upscaled), and returns JPEG bytes at [quality]. Returns null when
  /// the input can't be decoded (caller treats null as "no usable cover").
  static Uint8List? downscaleJpeg(
    List<int> bytes, {
    int maxW = maxWidth,
    int maxH = maxHeight,
    int quality = jpegQuality,
  }) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(Uint8List.fromList(bytes));
    } on Object {
      // The `image` package can throw (not just return null) on malformed
      // input; treat any failure as "not an image".
      return null;
    }
    if (decoded == null) return null;

    final img.Image fitted;
    if (decoded.width <= maxW && decoded.height <= maxH) {
      // Already within bounds — re-encode without upscaling.
      fitted = decoded;
    } else {
      // Scale by the dimension that needs the most reduction, aspect preserved.
      final widthRatio = maxW / decoded.width;
      final heightRatio = maxH / decoded.height;
      final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;
      fitted = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round().clamp(1, maxW),
        height: (decoded.height * ratio).round().clamp(1, maxH),
        interpolation: img.Interpolation.average,
      );
    }
    return img.encodeJpg(fitted, quality: quality);
  }
}
