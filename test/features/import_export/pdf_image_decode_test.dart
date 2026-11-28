import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_image_decode.dart';

import '../../support/pdf_tile_fakes.dart';

void main() {
  group('decodePdfImage', () {
    test('a real picture becomes a picture of the document', () {
      final doc = PdfDocument();
      final image = decodePdfImage(doc, tinyPngPicture);
      expect(image.width, 1);
      expect(image.height, 1);
    });

    test('bytes that are no picture throw', () {
      expect(
        () => decodePdfImage(PdfDocument(), notAPicture),
        throwsA(anything),
      );
    });
  });

  group('tryDecodePdfImage (the logo and the footer icon)', () {
    test('a real picture is decoded', () {
      expect(tryDecodePdfImage(PdfDocument(), tinyPngPicture), isNotNull);
    });

    test('no bytes, or bytes that are no picture, are skipped: a bad logo '
        'must not stop an export', () {
      final doc = PdfDocument();
      expect(tryDecodePdfImage(doc, null), isNull);
      expect(tryDecodePdfImage(doc, Uint8List(0)), isNull);
      expect(tryDecodePdfImage(doc, notAPicture), isNull);
    });

    test('any other error of the decoder is skipped too', () {
      expect(
        tryDecodePdfImage(
          PdfDocument(),
          tinyPngPicture,
          decode: (_, _) => throw StateError('decoder bug'),
        ),
        isNull,
      );
    });

    test('running out of memory is NOT skipped: it is passed on', () {
      expect(
        () => tryDecodePdfImage(
          PdfDocument(),
          tinyPngPicture,
          decode: (_, _) => throw const OutOfMemoryError(),
        ),
        throwsA(isA<OutOfMemoryError>()),
      );
    });
  });
}
