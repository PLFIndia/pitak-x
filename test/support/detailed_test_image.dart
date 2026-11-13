import 'package:image/image.dart' as img;

/// A test picture with detail in it (a colour pattern, not one flat colour).
///
/// Why not a blank picture: a blank picture compresses to almost the same
/// bytes at every JPEG quality, so a test could not tell quality 70 from
/// quality 80. This pattern is the same on every run, so two encodes of it
/// with the same settings give identical bytes.
img.Image detailedTestImage({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 7 + pixel.y * 3) % 256
      ..g = (pixel.x * 5) % 256
      ..b = (pixel.y * 11) % 256;
  }
  return image;
}
