import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/library/domain/photo_cover_recipe.dart';

import '../../support/detailed_test_image.dart';

/// The size and quality of a photographed cover are a decision (2026-11-10),
/// not a detail: they set how large a backup with thousands of covers gets.
/// A change must therefore be a deliberate edit of the expectations below.
void main() {
  test('a photo cover is at most 240 x 360 at JPEG quality 70', () {
    expect(
      {
        'maxWidth': PhotoCoverRecipe.maxWidth,
        'maxHeight': PhotoCoverRecipe.maxHeight,
        'jpegQuality': PhotoCoverRecipe.jpegQuality,
      },
      {'maxWidth': 240, 'maxHeight': 360, 'jpegQuality': 70},
    );
  });

  test('the recipe never asks for more than the shared default', () {
    // The publish step uses the shared default and never enlarges a picture.
    // While the photo recipe stays within it, a photo cover is published at
    // the size it was stored.
    expect(
      PhotoCoverRecipe.maxWidth,
      lessThanOrEqualTo(ImageDownscaler.maxWidth),
    );
    expect(
      PhotoCoverRecipe.maxHeight,
      lessThanOrEqualTo(ImageDownscaler.maxHeight),
    );
  });

  test('a photo cover goes through the publish recipe at the same size', () {
    final capture = img.encodeJpg(detailedTestImage(width: 720, height: 1080));
    final stored = ImageDownscaler.downscaleJpeg(
      capture,
      maxW: PhotoCoverRecipe.maxWidth,
      maxH: PhotoCoverRecipe.maxHeight,
      quality: PhotoCoverRecipe.jpegQuality,
    )!;
    final storedPicture = img.decodeImage(stored)!;
    expect(storedPicture.width, 240);
    expect(storedPicture.height, 360);

    // The publish step: the same function with its defaults (400 x 600).
    final published = img.decodeImage(ImageDownscaler.downscaleJpeg(stored)!)!;
    expect(published.width, 240, reason: 'never enlarged');
    expect(published.height, 360, reason: 'never enlarged');
  });
}
