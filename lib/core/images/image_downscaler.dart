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
///
/// **Two entry points (N10-a, astra-review.md N10):**
///  - [ImageDownscaler.downscaleJpeg] — synchronous, pure. The single
///    implementation; what the tests exercise directly.
///  - [ImageDownscaler.downscaleJpegAsync] — the SAME function run in a
///    one-shot worker isolate (`Isolate.run`). App code should call this one:
///    decoding + resizing a multi-megapixel photo takes hundreds of
///    milliseconds, and on the UI isolate that is hundreds of milliseconds of
///    frozen frames. No secret ever passes through here (image bytes only), so
///    the isolate hop is safe under the "keep secrets out of isolates" rule.
library;

import 'dart:isolate';
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

  /// Max TOTAL pixels (width × height) accepted for a source frame (N10-a).
  /// [maxSourceDimension] alone still admits 8192 × 8192 = 67 Mpx — a 256 MiB
  /// transient buffer, and a blank PNG that size compresses to a few dozen
  /// KB, so it passes every byte cap upstream (the remote-cover fetch and the
  /// publish read-back accept arbitrary bytes). 40 Mpx is well above any
  /// phone camera still (12–16 Mpx after processing) and any poster, and
  /// caps the worst-case buffer at ~160 MiB. Checked from the header, before
  /// any pixel buffer exists.
  static const int maxSourcePixels = 40_000_000;

  /// Decodes [bytes], scales it to fit within [maxW]×[maxH] (aspect preserved,
  /// never upscaled), and returns JPEG bytes at [quality]. Returns null when
  /// the input can't be decoded (caller treats null as "no usable cover").
  ///
  /// Runs on the CALLING isolate — prefer [downscaleJpegAsync] from app code.
  static Uint8List? downscaleJpeg(
    List<int> bytes, {
    int maxW = maxWidth,
    int maxH = maxHeight,
    int quality = jpegQuality,
  }) {
    final raw = Uint8List.fromList(bytes);
    // Header-only pre-decode: reject absurd dimensions BEFORE the full decode
    // allocates the pixel buffer (see [maxSourceDimension] /
    // [maxSourcePixels]). Fail closed — undecodable or oversized input is "no
    // usable image".
    final img.Decoder decoder;
    try {
      final found = img.findDecoderForData(raw);
      final info = found?.startDecode(raw);
      if (found == null || info == null) return null;
      if (info.width > maxSourceDimension || info.height > maxSourceDimension) {
        return null;
      }
      if (info.width * info.height > maxSourcePixels) return null;
      decoder = found;
    } on Object {
      return null;
    }

    // N10-a: decode FRAME 0 ONLY. `decodeImage` (and `Decoder.decode` with no
    // frame) walks EVERY frame of an animated GIF / APNG / WebP, `copyResize`
    // then resizes every frame, and `encodeJpg` writes only the first — so
    // the extra frames were unbounded wasted work (frame count is not part of
    // any size guard). A cover is a still image: the first frame is exactly
    // what the app stores anyway.
    final img.Image? decoded;
    try {
      decoded = decoder.decodeFrame(0);
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

  /// [downscaleJpeg], run in a one-shot worker isolate so the UI isolate keeps
  /// rendering frames while a photo is decoded, resized and re-encoded.
  ///
  /// `Isolate.run` copies [bytes] into the worker and the JPEG back out; both
  /// are plain byte lists (no closures over app state, no `BuildContext`, no
  /// secrets). Any exception inside the worker is already turned into `null`
  /// by [downscaleJpeg], so this never throws for bad input.
  static Future<Uint8List?> downscaleJpegAsync(
    List<int> bytes, {
    int maxW = maxWidth,
    int maxH = maxHeight,
    int quality = jpegQuality,
  }) {
    // Copy once here so the closure captures a `Uint8List` (efficiently
    // transferable) rather than an arbitrary `List<int>` view.
    final raw = Uint8List.fromList(bytes);
    return Isolate.run(
      () => downscaleJpeg(raw, maxW: maxW, maxH: maxH, quality: quality),
      debugName: 'pitaka-image-downscale',
    );
  }
}
