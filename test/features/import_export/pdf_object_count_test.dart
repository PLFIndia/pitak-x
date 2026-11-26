import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_image_decode.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_object_count.dart';

import '../../support/pdf_tile_fakes.dart';

void main() {
  // Loading the bundled fonts needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the objects a document has before its first row', () {
    test('an empty document: only what the file itself adds', () {
      expect(pdfFixedStreamObjects(PdfDocument()), 1);
    });

    test('the built-in font costs nothing', () {
      final doc = PdfDocument();
      PdfFontResolver.fromBytes(doc, const []);
      PdfFontResolver.fromBytes(doc, const []);
      expect(pdfFixedStreamObjects(doc), 1);
    });

    test('each TrueType font is two objects', () async {
      final doc = PdfDocument();
      PdfFontResolver.fromBytes(doc, [
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      ]);
      expect(pdfFixedStreamObjects(doc), 1 + 2);
      PdfFontResolver.fromBytes(doc, [
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
      ]);
      expect(pdfFixedStreamObjects(doc), 1 + 2 + 4);
    });

    test('a picture with transparency is two objects, a JPEG one, and a file '
        'that is no picture none', () {
      final doc = PdfDocument();
      expect(tryDecodePdfImage(doc, tinyPngPicture), isNotNull);
      expect(pdfFixedStreamObjects(doc), 1 + 2);
      final jpeg = Uint8List.fromList(
        im.encodeJpg(im.Image(width: 8, height: 8)),
      );
      expect(tryDecodePdfImage(doc, jpeg), isNotNull);
      expect(pdfFixedStreamObjects(doc), 1 + 2 + 1);
      expect(tryDecodePdfImage(doc, notAPicture), isNull);
      expect(pdfFixedStreamObjects(doc), 1 + 2 + 1);
    });
  });

  group('the count', () {
    test('a page is one object and a picture two, on top of the fixed '
        'ones', () {
      final count = PdfObjectCount(fixedObjects: 5, maxObjects: 100);
      expect(count.objectsFor(pages: 0, pictures: 0), 5);
      expect(count.objectsFor(pages: 3, pictures: 0), 8);
      expect(count.objectsFor(pages: 3, pictures: 10), 28);
    });

    test('a list within the budget fits whole', () {
      final count = PdfObjectCount(fixedObjects: 5, maxObjects: 12)
        ..rowsDone(0, pages: 1, pictures: 0)
        ..rowsDone(1, pages: 1, pictures: 1)
        ..rowsDone(2, pages: 1, pictures: 2)
        // Exactly at the budget: 5 + 1 + 2 * 3.
        ..rowsDone(3, pages: 1, pictures: 3);
      final estimate = count.estimate(rowsTotal: 3, pages: 1, pictures: 3);
      expect(estimate.objectsNeeded, 12);
      expect(estimate.objectsAllowed, 12);
      expect(estimate.fits, isTrue);
      expect(estimate.rowsTotal, 3);
      expect(estimate.rowsThatFit, 3);
    });

    test('one object over the budget: the rows before it fit', () {
      final count = PdfObjectCount(fixedObjects: 5, maxObjects: 11)
        ..rowsDone(0, pages: 1, pictures: 0)
        ..rowsDone(1, pages: 1, pictures: 1)
        ..rowsDone(2, pages: 1, pictures: 2)
        ..rowsDone(3, pages: 1, pictures: 3)
        ..rowsDone(4, pages: 2, pictures: 3);
      final estimate = count.estimate(rowsTotal: 4, pages: 2, pictures: 3);
      expect(estimate.objectsNeeded, 13);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsTotal, 4);
      expect(estimate.rowsThatFit, 2);
    });

    test('a row that needs a new PAGE can be the one that does not fit', () {
      final count = PdfObjectCount(fixedObjects: 1, maxObjects: 2)
        ..rowsDone(0, pages: 1, pictures: 0)
        ..rowsDone(1, pages: 1, pictures: 0)
        ..rowsDone(2, pages: 2, pictures: 0);
      final estimate = count.estimate(rowsTotal: 2, pages: 2, pictures: 0);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsThatFit, 1);
    });

    test('when not even the page without rows fits, no row fits', () {
      final count = PdfObjectCount(fixedObjects: 5, maxObjects: 5)
        ..rowsDone(0, pages: 1, pictures: 0)
        ..rowsDone(1, pages: 1, pictures: 0);
      final estimate = count.estimate(rowsTotal: 1, pages: 1, pictures: 0);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsThatFit, 0);
    });

    test('what is made after the last row is counted too', () {
      // The "(empty)" line of a list without rows is made after the report
      // of row 0: the estimate takes the numbers of the END of the pass.
      final count = PdfObjectCount(fixedObjects: 1, maxObjects: 3)
        ..rowsDone(0, pages: 1, pictures: 0);
      final estimate = count.estimate(rowsTotal: 0, pages: 1, pictures: 1);
      expect(estimate.objectsNeeded, 4);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsThatFit, 0);
    });
  });

  group('the budget of the app (decision D214)', () {
    test('one PDF may have 7,000 stream objects', () {
      // The number was looked for on devices and then CHOSEN by the
      // maintainer (`pdf_object_count.dart` and ADR 0033 say what was seen):
      // a higher one lets a longer list through and leaves the rest of the
      // app less room. Changing it is a decision, not a tidy-up, which is
      // why it stands here a second time.
      expect(pdfStreamObjectBudget, 7000);
    });
  });
}
