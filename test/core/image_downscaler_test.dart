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

    test('a very wide image is bounded by width', () {
      final src = img.encodePng(img.Image(width: 2000, height: 400));
      final decoded = img.decodeImage(ImageDownscaler.downscaleJpeg(src)!)!;
      expect(decoded.width, lessThanOrEqualTo(400));
      expect(decoded.height, lessThanOrEqualTo(600));
    });
  });
}
