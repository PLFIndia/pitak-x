import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:pitaka/features/import_export/application/export_library_use_case.dart'
    show defaultPdfLabels, kPdfFooterAttribution;
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_tiles.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

import '../../support/pdf_tile_fakes.dart';

void main() {
  // Asset loading (fonts) needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const renderer = PdfLibraryRenderer();

  List<PrintColumn> cols() =>
      resolvePrintColumns(PdfColumn.defaultSelection, defaultPdfLabels());

  // The bundled Latin + Devanagari faces are enough to exercise the resolver.
  Future<PdfFontBundle> regular() async => [
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
  ];
  Future<PdfFontBundle> bold() async => [
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
  ];

  // A rendered PDF must start with the "%PDF-" magic.
  void expectValidPdf(List<int> bytes) {
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  }

  test('renders an empty library to a valid PDF', () async {
    final bytes = await renderer.render(
      libraryName: 'My Library',
      books: const [],
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('renders a small Latin library to a valid PDF', () async {
    final books = [
      const CatalogueItem(title: 'A Book', author: 'An Author', copyCount: 2),
      const CatalogueItem(title: 'Another', isbn: '978-1', publishedYear: 2020),
    ];
    final bytes = await renderer.render(
      libraryName: 'Test Lib',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  group('text that needs shaping (ADR 0033)', () {
    const books = [
      CatalogueItem(title: 'भारत: गांधी के बाद', author: 'Ramachandra Guha'),
      CatalogueItem(title: 'गोदान', author: 'प्रेमचंद'),
    ];

    test('without a rasterizer the run ENDS: such text is never written '
        'unshaped, even when a font of its script is fed', () async {
      // Until 2026-11 this render went through and wrote the Devanagari
      // with `drawString`, letter after letter, which draws it wrongly.
      await expectLater(
        renderer.render(
          libraryName: 'मेरी लाइब्रेरी',
          books: books,
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          regularFonts: await regular(),
          boldFonts: await bold(),
        ),
        throwsA(isA<PdfTextPictureMissing>()),
      );
    });

    test('with a rasterizer each such text is a picture in the finished '
        'file, and the Latin text beside it is not', () async {
      final raster = CountingPdfRasterizer();
      final bytes = await renderer.render(
        libraryName: 'मेरी लाइब्रेरी',
        books: books,
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        regularFonts: await regular(),
        boldFonts: await bold(),
        textRasterizer: raster,
      );
      expectValidPdf(bytes);
      expect(
        raster.runs,
        unorderedEquals([
          'मेरी लाइब्रेरी',
          'भारत: गांधी के बाद',
          'गोदान',
          'प्रेमचंद',
        ]),
      );
      // Each picture is two objects of the file (pixels and transparency).
      expect(countPdfPictureObjects(bytes), 2 * raster.runs.length);
    });

    test('the name of the library is asked of the BOLD font and a row of the '
        'regular one', () async {
      // Regular is the Latin face; bold is left to the built-in Helvetica,
      // which has no "Š". So the name needs a picture and the row does not.
      final raster = CountingPdfRasterizer();
      await renderer.render(
        libraryName: 'Šárka’s Library',
        books: const [CatalogueItem(title: 'Šárka')],
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        regularFonts: [
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        ],
        textRasterizer: raster,
      );
      expect(raster.runs, ['Šárka’s Library']);
    });

    test('a Latin library, set up as the app sets it up (the Latin fonts and '
        'a rasterizer), holds no picture at all', () async {
      final raster = CountingPdfRasterizer();
      final bytes = await renderer.render(
        libraryName: 'Riverside Library',
        subtitle: 'Donated by Ram Sharma',
        books: List.generate(
          200,
          (i) => CatalogueItem(
            title: 'Šárka’s book number $i – a long title that wraps',
            author: 'Author $i',
            isbn: '9780000${i.toString().padLeft(6, '0')}',
            publishedYear: 1900 + (i % 120),
          ),
        ),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        regularFonts: [
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        ],
        boldFonts: [await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')],
        textRasterizer: raster,
      );
      expectValidPdf(bytes);
      expect(raster.runs, isEmpty);
      expect(countPdfPictureObjects(bytes), 0);
    });
  });

  test('paginates a large library without throwing', () async {
    final books = List.generate(
      200,
      (i) => CatalogueItem(title: 'Book number $i', author: 'Author $i'),
    );
    final bytes = await renderer.render(
      libraryName: 'Big Library',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  group('subtitle (filtered exports)', () {
    test('a subtitle renders a valid PDF, with or without a logo', () async {
      final logo = (await rootBundle.load(
        'assets/branding/app_icon.png',
      )).buffer.asUint8List();
      for (final logoBytes in [null, logo]) {
        final bytes = await renderer.render(
          libraryName: 'Riverside Library',
          subtitle: 'Donated by Ram Sharma',
          books: const [CatalogueItem(title: 'Godaan', author: 'Premchand')],
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          regularFonts: await regular(),
          boldFonts: await bold(),
          logoBytes: logoBytes,
        );
        expectValidPdf(bytes);
      }
    });

    test(
      'the subtitle is shaped once as page chrome, before any row',
      () async {
        final raster = CountingPdfRasterizer();
        // In Devanagari: a Latin subtitle is real text and is never
        // handed to the rasterizer.
        const subtitle = 'राम शर्मा द्वारा दान';
        await renderer.render(
          libraryName: 'Riverside Library',
          subtitle: subtitle,
          books: const [
            CatalogueItem(title: 'गोदान'),
            CatalogueItem(title: 'निर्मला'),
          ],
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          textRasterizer: raster,
        );
        final subtitleAt = raster.runs.indexOf(subtitle);
        expect(subtitleAt, isNot(-1));
        // Pinned chrome (not the per-row cache): rasterized exactly once and
        // before the first row's title.
        expect(raster.runs.where((r) => r == subtitle), hasLength(1));
        expect(raster.runs.indexOf('गोदान'), isNot(-1));
        expect(subtitleAt, lessThan(raster.runs.indexOf('गोदान')));
      },
    );

    test('a blank subtitle draws nothing', () async {
      final raster = CountingPdfRasterizer();
      await renderer.render(
        libraryName: 'पुस्तकालय',
        subtitle: '   ',
        books: const [CatalogueItem(title: 'गोदान')],
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: raster,
      );
      // The name and the title were asked for; a blank text never is.
      expect(raster.runs, ['पुस्तकालय', 'गोदान']);
    });
  });

  test('a bad logo/icon is skipped, not fatal', () async {
    final bytes = await renderer.render(
      libraryName: 'Lib',
      books: const [CatalogueItem(title: 'X')],
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      logoBytes: Uint8List.fromList([1, 2, 3, 4]),
      footerIconBytes: Uint8List.fromList([5, 6, 7, 8]),
    );
    expectValidPdf(bytes);
  });

  group('N10-e — bounded tiles, progress, cancel (shaped-image mode)', () {
    // Every title and author is unique and in Devanagari, so each is a
    // picture of its own and nothing dedups: the count of pictures is the
    // honest measure of what the renderer holds on to. Both are short enough
    // to stand on one line, so a row is exactly TWO pictures. The ISBN, the
    // year and the quantity are digits: real text, no picture.
    //
    // Keep these libraries small: every picture is two objects of the PDF
    // document with 64 KiB of buffer each while it is built.
    List<CatalogueItem> uniqueRows(int n) => List.generate(
      n,
      (i) => CatalogueItem(
        title: 'किताब संख्या $i',
        author: 'लेखक $i',
        isbn: '9780000${i.toString().padLeft(6, '0')}',
        publishedYear: 1900 + (i % 120),
        copyCount: 1 + (i % 3),
      ),
    );

    // The same rows in Latin letters: real text throughout.
    List<CatalogueItem> latinRows(int n) => List.generate(
      n,
      (i) => CatalogueItem(
        title: 'Unique title number $i with some words',
        author: 'Author $i',
        isbn: '9780000${i.toString().padLeft(6, '0')}',
      ),
    );

    test('the tile cache never holds more than the bound, and every picture '
        'asked for is in the finished file', () async {
      final raster = CountingPdfRasterizer();
      final seen = <PdfRenderProgress>[];
      const bound = 2;
      const rows = 250;
      final bytes = await renderer.render(
        libraryName: 'Big',
        books: uniqueRows(rows),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: raster,
        onProgress: seen.add,
        maxCachedTiles: bound,
      );
      expectValidPdf(bytes);
      // 250 rows × (title + author) is 500 distinct pictures — two orders of
      // magnitude over the bound — yet the cache must still top out at the
      // bound.
      expect(raster.runs, hasLength(2 * rows));
      expect(raster.runs.toSet().length, greaterThan(bound * 100));
      final peak = seen
          .map((p) => p.cachedTiles)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, bound, reason: 'peak cache $peak');
      // The pictures took the real embed path: two objects each.
      expect(countPdfPictureObjects(bytes), 2 * raster.runs.length);
    });

    test('the default bound is 512 tiles', () {
      expect(PdfLibraryRenderer.defaultMaxCachedTiles, 512);
    });

    test('rows are rasterized as they are drawn, not all up front', () async {
      final raster = CountingPdfRasterizer();
      final firstRowSeenAt = <int, int>{};
      var rowsDoneAtLastCallback = -1;
      await renderer.render(
        libraryName: 'Order',
        books: uniqueRows(120),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: raster,
        onProgress: (p) {
          rowsDoneAtLastCallback = p.rowsDone;
          // Record how many runs had been rasterized when each row finished.
          firstRowSeenAt.putIfAbsent(p.rowsDone, () => raster.runs.length);
        },
      );
      expect(rowsDoneAtLastCallback, 120);
      // When row 1 was reported done, the last row's author (a single run —
      // these authors never wrap) must NOT have been rasterized yet. HEAD
      // pre-rasterized every row before drawing any.
      final runsWhenRow1Done = firstRowSeenAt[1]!;
      final lastAuthorIndex = raster.runs.indexOf('लेखक 119');
      expect(lastAuthorIndex, isNot(-1));
      expect(lastAuthorIndex, greaterThanOrEqualTo(runsWhenRow1Done));
    });

    test('progress is monotonic, starts at 0 and ends at rowsTotal', () async {
      final seen = <PdfRenderProgress>[];
      await renderer.render(
        libraryName: 'Progress',
        books: uniqueRows(150),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: CountingPdfRasterizer(),
        onProgress: seen.add,
      );
      expect(seen.first.rowsDone, 0);
      expect(seen.first.pagesDone, greaterThanOrEqualTo(1));
      expect(seen.last.rowsDone, 150);
      expect(seen.last.rowsTotal, 150);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].rowsDone, greaterThanOrEqualTo(seen[i - 1].rowsDone));
        expect(seen[i].pagesDone, greaterThanOrEqualTo(seen[i - 1].pagesDone));
        expect(seen[i].rowsTotal, 150);
      }
      // 150 default-column rows do not fit one A4 page.
      expect(seen.last.pagesDone, greaterThan(1));
      expect(seen.last.fraction, 1.0);
    });

    test('progress is reported in Latin-only mode too', () async {
      final seen = <PdfRenderProgress>[];
      await renderer.render(
        libraryName: 'Latin',
        books: latinRows(10),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        regularFonts: await regular(),
        boldFonts: await bold(),
        onProgress: seen.add,
      );
      expect(seen.first.rowsDone, 0);
      expect(seen.last.rowsDone, 10);
      expect(seen.every((p) => p.cachedTiles == 0), isTrue);
    });

    test('cancel stops at the next row boundary and yields no bytes', () async {
      final raster = CountingPdfRasterizer();
      final token = RenderCancelToken();
      final books = uniqueRows(500);
      await expectLater(
        renderer.render(
          libraryName: 'Cancel',
          books: books,
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          textRasterizer: raster,
          cancelToken: token,
          onProgress: (p) {
            if (p.rowsDone == 10) token.cancel();
          },
        ),
        throwsA(isA<PdfRenderCancelled>()),
      );
      // Row 11 (index 10) may have been rasterized by the time the check
      // runs; row 12 must not have been (authors are single, unwrapped runs).
      expect(raster.runs, contains(books[9].author));
      expect(raster.runs, isNot(contains(books[11].author)));
      expect(raster.runs, isNot(contains(books.last.author)));
    });

    test('a token cancelled before the call renders nothing', () async {
      final raster = CountingPdfRasterizer();
      final token = RenderCancelToken()..cancel();
      await expectLater(
        renderer.render(
          libraryName: 'Pre-cancelled',
          books: uniqueRows(5),
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          textRasterizer: raster,
          cancelToken: token,
        ),
        throwsA(isA<PdfRenderCancelled>()),
      );
      expect(raster.runs, isEmpty);
    });

    test('the UI isolate is not starved: a timer fires mid-render', () async {
      // The real rasterizer awaits the engine per run; the fake yields once
      // per call the same way. A pending 1 ms timer must get its turn long
      // before a 150-row render (300 pictures) finishes.
      final sw = Stopwatch()..start();
      var firedAt = -1;
      final timer = Timer(const Duration(milliseconds: 1), () {
        firedAt = sw.elapsedMilliseconds;
      });
      await renderer.render(
        libraryName: 'Yield',
        books: uniqueRows(150),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: CountingPdfRasterizer(yieldPerCall: true),
      );
      final took = sw.elapsedMilliseconds;
      timer.cancel();
      expect(firedAt, isNot(-1), reason: 'timer never fired');
      expect(
        firedAt,
        lessThan(took ~/ 2),
        reason: 'fired at $firedAt ms, render took $took ms',
      );
    });

    test('the event loop gets a turn WHILE the finished file is written '
        '(ADR 0033)', () async {
      // Writing the file is the last part of a render, after the last row
      // was reported. The renderer asks the `pdf` package to pause between
      // the objects it writes, so that the progress row keeps moving and a
      // tap is heard; the package pauses only once 4 ms of work have passed
      // (`io/event_loop_balancer.dart`).
      //
      // So the file of this test must take TIME to write. Its pictures are
      // noise, which does not compress: 60 of them take about 90 ms on a
      // laptop of 2026, twenty times what one pause needs.
      final random = Random(7);
      final noise = im.Image(width: 375, height: 49, numChannels: 4);
      for (final pixel in noise) {
        pixel
          ..r = random.nextInt(256)
          ..g = random.nextInt(256)
          ..b = random.nextInt(256)
          ..a = random.nextInt(256);
      }
      final picture = Uint8List.fromList(im.encodePng(noise));

      // 30 rows, NOT a multiple of 20: the pass over the rows gives the
      // event loop a turn of its own after every 20th row, and a turn right
      // after the last row would hide what this test is about.
      const rows = 30;
      var turnsAfterTheLastRow = 0;
      Timer? probe;
      final bytes = await renderer.render(
        libraryName: 'Write',
        books: uniqueRows(rows),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: CountingPdfRasterizer(
          answer: (text) => CountingPdfRasterizer.tileOf(text, bytes: picture),
        ),
        onProgress: (p) {
          if (p.rowsDone == rows) {
            // Fires at the next turn of the event loop, whenever that is.
            probe = Timer(Duration.zero, () => turnsAfterTheLastRow += 1);
          }
        },
      );
      probe?.cancel();
      expectValidPdf(bytes);
      expect(countPdfPictureObjects(bytes), 2 * 2 * rows);
      expect(
        turnsAfterTheLastRow,
        1,
        reason:
            'between the last row and the finished file the event loop '
            'never got a turn: the file was written in one piece',
      );
    });
  });
}
