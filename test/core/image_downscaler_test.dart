import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// The GIF fixture below needs the decoder's recorded frame offsets to corrupt
// ONE frame surgically; this internal type is the only way to read them.
// ignore: implementation_imports
import 'package:image/src/formats/gif/gif_image_desc.dart';
import 'package:pitaka/core/images/image_downscaler.dart';

/// Byte offset of frame [f]'s image separator (0x2C) in [gif]: walk back from
/// the decoder's recorded LZW start over the local colour map (3 bytes per
/// colour) and the fixed 9-byte descriptor (x, y, w, h as uint16 + flags).
int _descriptorStart(Uint8List gif, InternalGifImageDesc f) {
  final colourMapBytes = f.colorMap == null ? 0 : f.colorMap!.numColors * 3;
  final start = f.inputPosition - colourMapBytes - 9 - 1;
  expect(gif[start], 0x2C, reason: 'expected a GIF image separator');
  return start;
}

/// A 3-frame 8×8 GIF whose SECOND frame is unreadable (its descriptor places
/// it outside the canvas, so `GifDecoder.decodeFrame(1)` returns null) while
/// frame 0 decodes fine. `image` 4.8.0's `decodeImage` decodes every frame
/// and returns null when ANY frame fails (`gif_decoder.dart:186-188`), so a
/// downscaler that decodes all frames sees "not an image"; one that decodes
/// frame 0 only sees a valid still.
Uint8List _threeFrameGifWithBrokenSecondFrame() {
  final anim = img.Image(width: 8, height: 8)
    ..frameDuration = 100
    ..addFrame(img.Image(width: 8, height: 8)..frameDuration = 100)
    ..addFrame(img.Image(width: 8, height: 8)..frameDuration = 100);
  final gif = img.encodeGif(anim);
  final decoder = img.GifDecoder()..startDecode(gif);
  final frames = decoder.info!.frames.cast<InternalGifImageDesc>();
  expect(frames.length, 3, reason: 'fixture must be animated');
  final bad = Uint8List.fromList(gif);
  final frame1 = _descriptorStart(bad, frames[1]);
  // x := 0xFFFF → `x + width > canvas width` → decodeFrame(1) == null.
  bad[frame1 + 1] = 0xFF;
  bad[frame1 + 2] = 0xFF;
  // Fixture sanity: frame 0 readable, frame 1 not, whole-animation decode
  // fails. If a future `image` release changes any of these, the test below
  // must be revisited rather than silently passing.
  final check = img.GifDecoder()..startDecode(bad);
  expect(check.decodeFrame(0), isNotNull);
  expect(check.decodeFrame(1), isNull);
  expect(img.decodeImage(bad), isNull);
  return bad;
}

void main() {
  group('ImageDownscaler.downscaleJpeg', () {
    test('shrinks an oversized image within 400x600, preserving aspect', () {
      // 1200x1800 (2:3) → should fit to 400x600.
      final src = img.encodePng(img.Image(width: 1200, height: 1800));
      final out = ImageDownscaler.downscaleJpeg(src);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, lessThanOrEqualTo(400));
      expect(decoded.height, lessThanOrEqualTo(600));
      // Aspect preserved (2:3 → 400x600).
      expect(decoded.width, 400);
      expect(decoded.height, 600);
    });

    test('does not upscale a small image', () {
      final src = img.encodePng(img.Image(width: 100, height: 150));
      final decoded = img.decodeImage(ImageDownscaler.downscaleJpeg(src)!)!;
      expect(decoded.width, 100);
      expect(decoded.height, 150);
    });

    test('encodes JPEG output', () {
      final src = img.encodePng(img.Image(width: 50, height: 50));
      final out = ImageDownscaler.downscaleJpeg(src)!;
      // JPEG magic bytes: FF D8 ... FF D9.
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
    });

    test('returns null for non-image bytes', () {
      expect(ImageDownscaler.downscaleJpeg([1, 2, 3, 4]), isNull);
    });

    // REVIEW_FINDINGS_2 S11: decodeImage allocates width×height×4 before any
    // bound — the header-dimension guard must reject first. A 8193×1 image
    // is byte-tiny and would decode FINE, so a null here proves the guard
    // fired rather than a decode failure.
    test('rejects oversized source dimensions before decoding', () {
      final wide = img.encodePng(img.Image(width: 8193, height: 1));
      expect(ImageDownscaler.downscaleJpeg(wide), isNull);
      final tall = img.encodePng(img.Image(width: 1, height: 8193));
      expect(ImageDownscaler.downscaleJpeg(tall), isNull);
      // Just under the cap still processes.
      final ok = img.encodePng(img.Image(width: 8192, height: 1));
      expect(ImageDownscaler.downscaleJpeg(ok), isNotNull);
    });

    // Regression for REVIEW_FINDINGS_2 S11 Blocker: `image` 4.3.0 carries
    // EXIF (incl. GPS) through decode → copyResize → encodeJpg, so the
    // downscaler must clear it explicitly or published JPEGs leak the
    // photographer's coordinates.
    test('strips EXIF incl. GPS IFD on the resize path', () {
      final src = img.Image(width: 800, height: 1200);
      src.exif.imageIfd[0x010F] = img.IfdValueAscii('TestMake'); // Make
      src.exif.gpsIfd[0x0002] = img.IfdValueRational(48, 1); // GPSLatitude
      final jpg = img.encodeJpg(src);
      // Sanity: the fixture really carries EXIF through an encode/decode.
      // (ExifData.hasTag only scans top-level IFDs, so the GPS sub-IFD is
      // checked via gpsIfd directly.)
      final roundTrip = img.decodeImage(jpg)!;
      expect(roundTrip.exif.hasTag(0x010F), isTrue);
      expect(roundTrip.exif.gpsIfd.isEmpty, isFalse);

      final out = img.decodeImage(ImageDownscaler.downscaleJpeg(jpg)!)!;
      // Check isEmpty FIRST: the gpsIfd/ifd0 getters lazily create empty
      // directories, which would dirty the container.
      expect(out.exif.isEmpty, isTrue);
      expect(out.exif.hasTag(0x010F), isFalse);
    });

    test('strips EXIF on the no-resize path (small image)', () {
      final src = img.Image(width: 100, height: 150);
      src.exif.imageIfd[0x010F] = img.IfdValueAscii('TestMake');
      src.exif.gpsIfd[0x0002] = img.IfdValueRational(48, 1);
      final jpg = img.encodeJpg(src);
      expect(img.decodeImage(jpg)!.exif.isEmpty, isFalse); // fixture sanity

      final out = img.decodeImage(ImageDownscaler.downscaleJpeg(jpg)!)!;
      expect(out.width, 100); // untouched dimensions: no-resize path taken
      expect(out.exif.isEmpty, isTrue);
    });

    test('a very wide image is bounded by width', () {
      final src = img.encodePng(img.Image(width: 2000, height: 400));
      final decoded = img.decodeImage(ImageDownscaler.downscaleJpeg(src)!)!;
      expect(decoded.width, lessThanOrEqualTo(400));
      expect(decoded.height, lessThanOrEqualTo(600));
    });
  });

  // N10-a (astra-review.md N10): the source-dimension guard bounded ONE
  // frame's width/height only. `image` 4.8.0 decodes EVERY frame of an
  // animated GIF/APNG/WebP when no frame is requested, resizes every frame
  // (`copy_resize.dart:95-97`) and then JPEG-encodes frame 0 alone — so N−1
  // frames of decode+resize were wasted work, and total decoded pixels were
  // unbounded by frame count. A cover is a still image: decode frame 0 only.
  group('N10-a — bounded decode work', () {
    test('an animated GIF is downscaled from frame 0 only', () {
      final gif = _threeFrameGifWithBrokenSecondFrame();
      // HEAD: decodeImage walks all frames, frame 1 fails → null ("not an
      // image"). Frame-0-only: a valid 8×8 JPEG.
      final out = ImageDownscaler.downscaleJpeg(gif);
      expect(out, isNotNull, reason: 'frame 0 is a perfectly good still');
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 8);
      expect(decoded.height, 8);
      expect(decoded.numFrames, 1, reason: 'the stored cover is a still');
    });

    test('a healthy animated GIF still produces a single-frame JPEG', () {
      final anim = img.Image(width: 20, height: 30)
        ..frameDuration = 100
        ..addFrame(img.Image(width: 20, height: 30)..frameDuration = 100);
      final gif = img.encodeGif(anim);
      expect(img.decodeImage(gif)!.numFrames, 2, reason: 'fixture sanity');
      final out = ImageDownscaler.downscaleJpeg(gif)!;
      final decoded = img.decodeImage(out)!;
      expect(decoded.numFrames, 1);
      expect(decoded.width, 20);
      expect(decoded.height, 30);
    });

    // The per-dimension cap (8192) alone admits 8192×8192 = 67 Mpx, a 256 MiB
    // transient buffer. A blank 6400×6400 PNG (41 Mpx) compresses to ~54 KB,
    // so it sails through every byte cap upstream — the pixel guard must fire
    // from the header, before any pixel buffer is allocated.
    test('rejects a source over maxSourcePixels before decoding', () {
      expect(
        ImageDownscaler.maxSourcePixels,
        lessThan(
          ImageDownscaler.maxSourceDimension *
              ImageDownscaler.maxSourceDimension,
        ),
        reason: 'the pixel cap must be tighter than the dimension cap',
      );
      final huge = img.encodePng(
        img.Image(width: 6400, height: 6400, numChannels: 1),
      );
      expect(6400 * 6400, greaterThan(ImageDownscaler.maxSourcePixels));
      final sw = Stopwatch()..start();
      expect(ImageDownscaler.downscaleJpeg(huge), isNull);
      // A header-only refusal is milliseconds; a full decode of 41 Mpx was
      // measured at ~850 ms on the dev machine. Generous bound, still far
      // below a decode.
      expect(
        sw.elapsedMilliseconds,
        lessThan(300),
        reason: 'refusal must not decode the pixel buffer',
      );
    });

    test('a source just under maxSourcePixels is still processed', () {
      // 6000×6000 = 36 Mpx < 40 Mpx; both sides ≤ 8192.
      final big = img.encodePng(
        img.Image(width: 6000, height: 6000, numChannels: 1),
      );
      expect(6000 * 6000, lessThan(ImageDownscaler.maxSourcePixels));
      final out = ImageDownscaler.downscaleJpeg(big);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, lessThanOrEqualTo(400));
      expect(decoded.height, lessThanOrEqualTo(600));
    });
  });

  // N10-a: the decode/resize/encode ran on the calling (UI) isolate at all
  // five call sites. `downscaleJpegAsync` runs the SAME pure function in a
  // one-shot worker isolate (`Isolate.run`), so a multi-megapixel capture no
  // longer freezes frames while it is processed.
  group('N10-a — downscaleJpegAsync', () {
    test('returns byte-identical output to the synchronous path', () async {
      final src = img.encodePng(img.Image(width: 1200, height: 1800));
      final sync = ImageDownscaler.downscaleJpeg(src)!;
      final async = await ImageDownscaler.downscaleJpegAsync(src);
      expect(async, isNotNull);
      expect(async, orderedEquals(sync));
    });

    test('forwards the size and quality arguments', () async {
      final src = img.encodePng(img.Image(width: 1200, height: 1800));
      final out = await ImageDownscaler.downscaleJpegAsync(
        src,
        maxW: 100,
        maxH: 100,
        quality: 50,
      );
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, lessThanOrEqualTo(100));
      expect(decoded.height, lessThanOrEqualTo(100));
    });

    test(
      'returns null for undecodable input (no throw across isolates)',
      () async {
        expect(await ImageDownscaler.downscaleJpegAsync([1, 2, 3, 4]), isNull);
      },
    );

    test('does not block the calling isolate while it works', () async {
      // A 36 Mpx decode+resize takes hundreds of ms synchronously (measured
      // ~850 ms for 41 Mpx). If that work ran on THIS isolate, a 1 ms timer
      // scheduled just before it could not fire until it finished.
      final big = img.encodePng(
        img.Image(width: 6000, height: 6000, numChannels: 1),
      );
      final fired = Completer<int>();
      final sw = Stopwatch()..start();
      Timer(const Duration(milliseconds: 1), () {
        fired.complete(sw.elapsedMilliseconds);
      });
      final work = ImageDownscaler.downscaleJpegAsync(big);
      final firedAt = await fired.future;
      final out = await work;
      final total = sw.elapsedMilliseconds;
      expect(out, isNotNull);
      expect(
        firedAt,
        lessThan(total ~/ 2),
        reason:
            'the timer must fire while the downscale is still running '
            '(fired at $firedAt ms, work took $total ms)',
      );
    });
  });
}
