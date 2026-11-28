import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_image_decode.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_tiles.dart';

import '../../support/pdf_tile_fakes.dart';

const _hindi = 'गोदान';
const _black = PdfColors.black;

void main() {
  // Loading the bundled fonts needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ByteData latinRegular;
  late ByteData latinBold;
  setUpAll(() async {
    latinRegular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    latinBold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  });

  /// A tile source over a fresh document. With [fonts] the two Latin faces
  /// are fed, as the app feeds them; without, the document has only the
  /// built-in Helvetica, which knows nothing above U+00FF.
  ({PdfDocument doc, PdfTextTiles tiles}) make({
    PdfTextRasterizer? rasterizer,
    bool fonts = true,
    bool boldFont = true,
    int maxEntries = 8,
    PdfImageDecoder decode = decodePdfImage,
    bool makePictures = true,
  }) {
    final doc = PdfDocument();
    final tiles = PdfTextTiles(
      doc,
      rasterizer,
      maxEntries,
      regular: PdfFontResolver.fromBytes(doc, fonts ? [latinRegular] : []),
      bold: PdfFontResolver.fromBytes(
        doc,
        fonts && boldFont ? [latinBold] : [],
      ),
      decode: decode,
      makePictures: makePictures,
    );
    return (doc: doc, tiles: tiles);
  }

  test('the stand-in picture of these tests really decodes', () {
    expect(im.decodeImage(tinyPngPicture), isNotNull);
    expect(im.decodeImage(notAPicture), isNull);
  });

  group('real text: no picture', () {
    test(
      'a plain text the font can draw never reaches the rasterizer',
      () async {
        final raster = CountingPdfRasterizer();
        final made = make(rasterizer: raster);
        final objectsBefore = made.doc.objects.length;
        const texts = [
          'Godan',
          '978-81-267-0000-1',
          '1936',
          'Šárka Dvořák',
          'War – and “Peace”…',
          '₹250',
          '#',
        ];
        for (final text in texts) {
          expect(await made.tiles.row(text, 12, _black), isNull, reason: text);
          expect(
            await made.tiles.pinned(text, 12, _black, bold: true),
            isNull,
            reason: text,
          );
        }
        expect(raster.runs, isEmpty);
        expect(made.tiles.cachedCount, 0, reason: 'plain texts take no key');
        expect(made.doc.objects.length, objectsBefore);
      },
    );

    test(
      'an empty text is nothing to draw, with or without a rasterizer',
      () async {
        final raster = CountingPdfRasterizer();
        for (final tiles in [make(rasterizer: raster).tiles, make().tiles]) {
          expect(await tiles.row('', 12, _black), isNull);
          expect(await tiles.pinned('', 12, _black, bold: false), isNull);
        }
        expect(raster.runs, isEmpty);
      },
    );
  });

  group('a picture', () {
    test('a text in Devanagari gets one, with the measures of the '
        'rasterizer', () async {
      final raster = CountingPdfRasterizer();
      final made = make(rasterizer: raster);
      final objectsBefore = made.doc.objects.length;
      final tile = await made.tiles.row(_hindi, 12, _black);
      expect(tile, isNotNull);
      expect(raster.runs, [_hindi]);
      // The pixels and their transparency: two objects of the document.
      expect(made.doc.objects.length, objectsBefore + 2);
      expect(tile!.widthPt, _hindi.length * 6.0);
      expect(tile.heightPt, 14);
      expect(tile.baselinePt, 11);
    });

    test('ONE character off the plain list makes the whole text one', () async {
      final raster = CountingPdfRasterizer();
      final tiles = make(rasterizer: raster).tiles;
      expect(await tiles.row('Godan $_hindi', 12, _black), isNotNull);
      expect(raster.runs, ['Godan $_hindi']);
    });

    test('a plain text with a character the font lacks gets one', () async {
      // No fonts fed: the built-in Helvetica has no dash above U+00FF.
      final raster = CountingPdfRasterizer();
      final tiles = make(rasterizer: raster, fonts: false).tiles;
      expect(await tiles.row('Godan', 12, _black), isNull);
      expect(await tiles.row('War – Peace', 12, _black), isNotNull);
      expect(raster.runs, ['War – Peace']);
    });

    test('the weight decides which font is asked', () async {
      // Regular is the fed Latin face; bold is only the built-in Helvetica.
      final raster = CountingPdfRasterizer();
      final tiles = make(rasterizer: raster, boldFont: false).tiles;
      expect(await tiles.row('Šárka', 12, _black), isNull);
      expect(await tiles.pinned('Šárka', 12, _black, bold: false), isNull);
      expect(await tiles.pinned('Šárka', 12, _black, bold: true), isNotNull);
      expect(raster.runs, ['Šárka']);
    });

    test('a row text is asked for once while its key is cached, and a plain '
        'text takes no key', () async {
      final raster = CountingPdfRasterizer();
      final tiles = make(rasterizer: raster).tiles;
      final first = await tiles.row(_hindi, 12, _black);
      final again = await tiles.row(_hindi, 12, _black);
      expect(identical(first, again), isTrue);
      expect(raster.runs, [_hindi]);
      expect(tiles.cachedCount, 1);
      await tiles.row('Godan', 12, _black);
      expect(tiles.cachedCount, 1);
    });
  });

  group('a text that needs a picture and gets none ends the run', () {
    final cases = <String, PdfTextRasterizer? Function()>{
      'no rasterizer at all': () => null,
      'the rasterizer answers nothing': () =>
          CountingPdfRasterizer(answer: (_) => null),
      'bytes that are no picture': () => CountingPdfRasterizer(
        answer: (t) => CountingPdfRasterizer.tileOf(t, bytes: notAPicture),
      ),
      'no bytes': () => CountingPdfRasterizer(
        answer: (t) => CountingPdfRasterizer.tileOf(t, bytes: Uint8List(0)),
      ),
    };
    for (final MapEntry(key: name, value: rasterizer) in cases.entries) {
      test(name, () async {
        final tiles = make(rasterizer: rasterizer()).tiles;
        await expectLater(
          tiles.row(_hindi, 12, _black),
          throwsA(isA<PdfTextPictureMissing>()),
        );
        await expectLater(
          tiles.pinned(_hindi, 20, _black, bold: true),
          throwsA(isA<PdfTextPictureMissing>()),
        );
        expect(tiles.cachedCount, 0, reason: 'a failed text leaves no key');
      });
    }

    test('the error names no text of the catalogue', () {
      // A title is the user's data: it must not travel in an error's text,
      // from where it could reach a log.
      expect(const PdfTextPictureMissing().toString(), 'PdfTextPictureMissing');
    });
  });

  group('a counting pass (ADR 0033): the same decisions, no picture made', () {
    /// A rasterizer that must never be reached.
    CountingPdfRasterizer forbidden() => CountingPdfRasterizer(
      answer: (text) => fail('a counting pass asked for a picture of $text'),
    );

    test('a text that needs a picture is counted and NOT made', () async {
      final raster = forbidden();
      final made = make(rasterizer: raster, makePictures: false);
      final objectsBefore = made.doc.objects.length;
      // The answer of a counting pass is always null: nothing is drawn.
      expect(await made.tiles.row(_hindi, 12, _black), isNull);
      expect(raster.runs, isEmpty);
      expect(made.doc.objects.length, objectsBefore);
      expect(made.tiles.picturesMade, 1);
      expect(
        made.tiles.cachedCount,
        1,
        reason: 'it takes its key all the same',
      );
    });

    test('it needs no rasterizer at all', () async {
      final tiles = make(makePictures: false).tiles;
      expect(await tiles.row(_hindi, 12, _black), isNull);
      expect(await tiles.pinned(_hindi, 20, _black, bold: true), isNull);
      expect(tiles.picturesMade, 2);
    });

    test('real text is not counted', () async {
      final tiles = make(makePictures: false).tiles;
      await tiles.row('Godan', 12, _black);
      await tiles.row('', 12, _black);
      await tiles.pinned('Riverside Library', 20, _black, bold: true);
      expect(tiles.picturesMade, 0);
      expect(tiles.cachedCount, 0);
    });

    test('the page chrome is counted every time: it has no cache', () async {
      final tiles = make(makePictures: false).tiles;
      await tiles.pinned(_hindi, 20, _black, bold: true);
      await tiles.pinned(_hindi, 20, _black, bold: true);
      expect(tiles.picturesMade, 2);
      expect(tiles.cachedCount, 0);
    });

    test('a row text is counted once while its key is cached, and AGAIN '
        'when it comes back after its key was forgotten', () async {
      final tiles = make(makePictures: false, maxEntries: 2).tiles;
      await tiles.row('अ', 12, _black);
      await tiles.row('अ', 12, _black);
      expect(tiles.picturesMade, 1);
      await tiles.row('आ', 12, _black);
      // The third key pushes the oldest one out.
      await tiles.row('इ', 12, _black);
      expect(tiles.picturesMade, 3);
      expect(tiles.cachedCount, 2);
      await tiles.row('अ', 12, _black);
      expect(tiles.picturesMade, 4);
    });

    test('a hit makes its key the newest, as in a drawing pass', () async {
      final tiles = make(makePictures: false, maxEntries: 2).tiles;
      await tiles.row('अ', 12, _black);
      await tiles.row('आ', 12, _black);
      // A hit: now आ is the oldest key, and the next new text pushes IT out.
      await tiles.row('अ', 12, _black);
      await tiles.row('इ', 12, _black);
      expect(tiles.picturesMade, 3);
      await tiles.row('अ', 12, _black);
      expect(tiles.picturesMade, 3, reason: 'अ was still cached');
      await tiles.row('आ', 12, _black);
      expect(tiles.picturesMade, 4, reason: 'आ had been forgotten');
    });

    test('counting and drawing agree, text for text', () async {
      // The same calls against a drawing and a counting tile source: the
      // count must be the number of pictures the drawing really made.
      const calls = [
        'अ',
        'Godan',
        'आ',
        'अ',
        'इ',
        'ई',
        'अ',
        '',
        'आ',
        'आ',
        '1936',
        'उ',
        'इ',
        'अ',
        'War – Peace',
        'ई',
        'उ',
        'अ',
      ];
      for (final bound in [1, 2, 3, 4, 64]) {
        final raster = CountingPdfRasterizer();
        final drawing = make(rasterizer: raster, maxEntries: bound);
        final counting = make(makePictures: false, maxEntries: bound);
        final objectsBefore = drawing.doc.objects.length;
        for (final text in calls) {
          await drawing.tiles.row(text, 12, _black);
          await counting.tiles.row(text, 12, _black);
          expect(
            counting.tiles.picturesMade,
            drawing.tiles.picturesMade,
            reason: 'after "$text" at a bound of $bound',
          );
          expect(counting.tiles.cachedCount, drawing.tiles.cachedCount);
        }
        await drawing.tiles.pinned(_hindi, 20, _black, bold: true);
        await counting.tiles.pinned(_hindi, 20, _black, bold: true);
        expect(counting.tiles.picturesMade, drawing.tiles.picturesMade);
        // What was counted is what was made: one call of the rasterizer and
        // two objects of the document for each.
        expect(drawing.tiles.picturesMade, raster.runs.length);
        expect(
          drawing.doc.objects.length,
          objectsBefore + 2 * drawing.tiles.picturesMade,
        );
      }
    });

    test('in a drawing pass a picture that could not be made is not '
        'counted', () async {
      final tiles = make(
        rasterizer: CountingPdfRasterizer(answer: (_) => null),
      ).tiles;
      await expectLater(
        tiles.row(_hindi, 12, _black),
        throwsA(isA<PdfTextPictureMissing>()),
      );
      expect(tiles.picturesMade, 0);
    });
  });

  group('running out of memory is passed on as it is', () {
    test('from the rasterizer', () async {
      final tiles = make(
        rasterizer: CountingPdfRasterizer(
          answer: (_) => throw const OutOfMemoryError(),
        ),
      ).tiles;
      await expectLater(
        tiles.row(_hindi, 12, _black),
        throwsA(isA<OutOfMemoryError>()),
      );
    });

    test('from the decoding of the picture', () async {
      final tiles = make(
        rasterizer: CountingPdfRasterizer(),
        decode: (_, _) => throw const OutOfMemoryError(),
      ).tiles;
      await expectLater(
        tiles.row(_hindi, 12, _black),
        throwsA(isA<OutOfMemoryError>()),
      );
    });
  });
}
