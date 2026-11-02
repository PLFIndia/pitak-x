import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';

/// Plan CV3 / ADR 0020 Decision 3: the rendition NUMBER and the recipe it
/// stands for move together.
///
/// Why this test exists (beginner note): from ADR 0020 on, a cover that is
/// already online is reused without being produced again when the record
/// says it was made with rendition `current`. If someone changed the size or
/// quality but forgot the number, old covers would never be updated. If they
/// changed the number for nothing, every cover would be produced again once.
/// So a change of either side must be a deliberate, reviewed edit of the
/// expectations below.
void main() {
  test('rendition 1 is exactly 400 x 600 at JPEG quality 80', () {
    expect(
      {
        'rendition': PublishCoverRendition.current,
        'maxWidth': PublishCoverRendition.maxWidth,
        'maxHeight': PublishCoverRendition.maxHeight,
        'jpegQuality': PublishCoverRendition.jpegQuality,
      },
      {'rendition': 1, 'maxWidth': 400, 'maxHeight': 600, 'jpegQuality': 80},
      reason:
          'Changing a parameter needs a new PublishCoverRendition.current '
          '(and new expectations here), so every published cover is made '
          'once more (ADR 0020 Decision 3).',
    );
  });

  test('the publish readers use ImageDownscaler defaults = the rendition', () {
    // Both publish readers (the local cover reader and the bounded
    // remote-cover download) call `downscaleJpegAsync` with its defaults.
    expect(ImageDownscaler.maxWidth, PublishCoverRendition.maxWidth);
    expect(ImageDownscaler.maxHeight, PublishCoverRendition.maxHeight);
    expect(ImageDownscaler.jpegQuality, PublishCoverRendition.jpegQuality);
  });

  group('tryParse: anything but a positive whole number is unknown', () {
    test('a stored rendition is read back', () {
      expect(PublishCoverRendition.tryParse(1), 1);
      expect(PublishCoverRendition.tryParse(7), 7);
    });

    test('missing, zero, negative or the wrong type reads as unknown', () {
      for (final raw in <Object?>[null, 0, -1, '1', 1.0, true, const <int>[]]) {
        expect(PublishCoverRendition.tryParse(raw), isNull, reason: '$raw');
      }
    });
  });
}
