import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/images/image_downscaler.dart';

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
}
