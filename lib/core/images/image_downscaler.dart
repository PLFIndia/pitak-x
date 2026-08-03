/// Cover image downscaling (core util, AGENTS.md §3.1).
///
/// Port of Kotlin `ImagePipeline.downscaleForPublish`: fit within a max
/// width×height (book aspect, default 400×600) preserving aspect ratio, then
/// re-encode as JPEG at a fixed quality (default 80). Used both for the stored
/// book cover (camera capture) and the published cover bundle, so a captured
/// photo never lands at multi-megapixel size on disk or in a git push.
///
/// All EXIF metadata (including GPS) is stripped before encoding — see the
/// comment in [ImageDownscaler.downscaleJpeg].
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

  /// Max width/height (pixels) accepted for a SOURCE image before the full
  /// decode is attempted (decoder-bomb guard, REVIEW_FINDINGS_2 S11):
  /// `decodeImage` allocates width×height×4 bytes up front, so a crafted
  /// 20k×20k JPEG (~1.6 GiB) would OOM the isolate before any size bound
  /// applied. Every legit input is pre-bounded by image_picker (≤ 2048 px),
  /// so 8192 is far above real photos while capping the worst-case
  /// transient allocation at 8192×8192×4 = 256 MiB.
  static const int maxSourceDimension = 8192;

  /// Decodes [bytes], scales it to fit within [maxW]×[maxH] (aspect preserved,
  /// never upscaled), and returns JPEG bytes at [quality]. Returns null when
  /// the input can't be decoded (caller treats null as "no usable cover").
  static Uint8List? downscaleJpeg(
    List<int> bytes, {
    int maxW = maxWidth,
    int maxH = maxHeight,
    int quality = jpegQuality,
  }) {
    final raw = Uint8List.fromList(bytes);
    // Header-only pre-decode: reject absurd dimensions BEFORE the full decode
    // allocates the pixel buffer (see [maxSourceDimension]). Fail closed —
    // undecodable or oversized input is "no usable image".
    try {
      final decoder = img.findDecoderForData(raw);
      final info = decoder?.startDecode(raw);
      if (info == null) return null;
      if (info.width > maxSourceDimension || info.height > maxSourceDimension) {
        return null;
      }
    } on Object {
      return null;
    }

    final img.Image? decoded;
    try {
      decoded = img.decodeImage(raw);
    } on Object {
      // The `image` package can throw (not just return null) on malformed
      // input; treat any failure as "not an image".
      return null;
    }
    if (decoded == null) return null;

    // Privacy (AGENTS.md §2a): strip ALL EXIF metadata — including GPS
    // coordinates — before re-encoding. `image` 4.x carries EXIF through
    // decode → copyResize → encodeJpg (the resize clones `Image.exif` and the
    // JPEG encoder writes it back as APP1), so a gallery photo with location
    // tagging would otherwise publish the photographer's coordinates onto the
    // public site. Clearing here covers covers, posters and logos at the
    // single choke point, on both the resize and no-resize paths.
    decoded.exif = img.ExifData();

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
