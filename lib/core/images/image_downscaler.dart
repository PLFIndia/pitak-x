/// Cover image downscaling (core util, AGENTS.md §3.1).
///
/// Port of Kotlin `ImagePipeline.downscaleForPublish`: fit within a max
/// width×height (book aspect, default 400×600) preserving aspect ratio, then
/// re-encode as JPEG at a fixed quality (default 80), so a picture never
/// lands at multi-megapixel size on disk or on a published site.
///
/// Where each size applies (the caller chooses; this file only holds the
/// shared default):
///  - the default, 400×600 at quality 80: the publish step (the local cover
///    reader and the bounded remote-cover download), a remote cover saved to
///    the phone through that same download (an ISBN look-up), the library
///    logo, and covers fetched from a published site;
///  - 240×360 at quality 70: a cover photographed in the app. The two capture
///    controllers pass the numbers of `PhotoCoverRecipe` (library domain);
///  - 1080×1440: event posters (`events_providers.dart`).
///
/// All EXIF metadata (including GPS) is stripped before encoding — see the
/// comment in [ImageDownscaler.downscaleJpeg]. So is the source's colour
/// profile. Transparency is thrown away without blending (JPEG has none).
/// These three rules make the output independent of what a new `image`
/// version does with metadata and transparency.
///
/// Published covers depend on this function: a publish reuses a cover that
/// is already online when it was made with the same recipe (ADR 0020,
/// `PublishCoverRendition` in the publish domain). Changing on purpose HOW
/// this function resizes or encodes (interpolation, metadata rule, frame
/// choice) therefore also needs a new `PublishCoverRendition.current`, so
/// every published cover is made once more. A new `image` package version
/// that merely encodes the same picture into other bytes does not.
///
/// Pure-Dart via the `image` package (decode/resize/encode) — no platform
/// dependency, so it is unit-testable and runs the same on every target.
///
/// **Two entry points (review finding N10-a: image decode/encode used to run
/// unbounded on the UI isolate):**
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
    // The `image` package's own pixel limit (since 4.10.2 / 4.12.0), set to
    // OUR limit. Why here and not once at start-up (beginner note): the
    // package keeps this number in a static field, and every isolate has its
    // own statics. This function also runs in a worker isolate
    // ([downscaleJpegAsync]), so it sets the number each time it runs. The
    // package's default is 2^28 pixels, about seven times our limit. Ours
    // is checked from the header just below; this one makes the decoder
    // itself refuse to go further, also for frames and sub-images the
    // header does not announce. `findDecoderForData` builds its decoders
    // with this default, which is why it is set BEFORE that call.
    img.Decoder.defaultMaxPixels = maxSourcePixels;
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
    decoded
      ..exif = img.ExifData()
      // The same rule for the colour profile (ICC) of the source picture.
      // Until `image` 4.3.0 the JPEG encoder never wrote one, so no stored
      // or published picture has one. Newer versions read the profile from
      // JPEG, PNG and WebP sources and write it into the output, which
      // would copy a block of the source's metadata into every such picture
      // and make it up to several kilobytes larger. Dropped here, so the
      // output stays what it has always been (decision point 12 of the
      // backup rework, 2026-11-10).
      ..iccProfile = null;

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
    return img.encodeJpg(_withoutTransparency(fitted), quality: quality);
  }

  /// [image] with its transparency thrown away: every pixel keeps the red,
  /// green and blue values it has, and nothing is blended.
  ///
  /// Why (beginner note; decision point 12 of the backup rework, 2026-11-10):
  /// JPEG cannot store transparency. Until `image` 4.3.0 the encoder wrote
  /// each pixel's stored colour and ignored how transparent it was. Since
  /// 4.5.3 it blends transparent pixels onto white instead, so a logo or a
  /// poster picked as a PNG would suddenly look different. The maintainer
  /// chose to keep the picture the app has always made. The transparency is
  /// therefore removed HERE, before the encoder sees it, and the result no
  /// longer depends on what the package does with transparency.
  ///
  /// Changing this on purpose changes how published pictures look and needs
  /// a new `PublishCoverRendition.current` (ADR 0020).
  static img.Image _withoutTransparency(img.Image image) {
    // The encoder blends exactly when a pixel has a fourth channel (read in
    // `image` 4.12.0, `jpeg_encoder.dart`). A palette picture counts by the
    // channels of its palette, which `numChannels` reports.
    if (image.numChannels <= 3) return image;
    final opaque = img.Image(width: image.width, height: image.height);
    for (final pixel in image) {
      // Read as the old encoder read it: brought to 8 bits per channel
      // first (a 16-bit PNG), then red, green and blue as they are.
      final colour = pixel.format == img.Format.uint8
          ? pixel
          : pixel.convert(format: img.Format.uint8);
      opaque.setPixelRgb(pixel.x, pixel.y, colour.r, colour.g, colour.b);
    }
    return opaque;
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
