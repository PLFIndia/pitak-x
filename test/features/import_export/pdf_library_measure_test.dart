/// The count before a PDF is made (ADR 0033): `measure` must say what
/// `render` will really put into the file, for every kind of list, and say
/// it without making a single picture.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart'
    show defaultPdfLabels, kPdfFooterAttribution;
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_pass.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_object_count.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

import '../../support/pdf_tile_fakes.dart';

void main() {
  // Asset loading (fonts, the icons) needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  List<PrintColumn> cols() =>
      resolvePrintColumns(PdfColumn.defaultSelection, defaultPdfLabels());
  List<PrintColumn> allCols() =>
      resolvePrintColumns(PdfColumn.values.toList(), defaultPdfLabels());

  // As the app feeds them: the Latin face of each weight.
  late PdfFontBundle regular;
  late PdfFontBundle bold;
  late Uint8List logoPng;
  late Uint8List iconPng;
  setUpAll(() async {
    regular = [await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')];
    bold = [await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')];
    logoPng = (await rootBundle.load(
      'assets/branding/app_icon.png',
    )).buffer.asUint8List();
    iconPng = (await rootBundle.load(
      'assets/pdf/app_icon.png',
    )).buffer.asUint8List();
  });

  // Latin rows: real text throughout. Some titles wrap to two lines.
  List<CatalogueItem> latinRows(int n) => List.generate(
    n,
    (i) => CatalogueItem(
      title: i.isEven
          ? 'Unique title number $i with some more words to wrap it'
          : 'Short title $i',
      author: 'Author ${i % 9}',
      isbn: '9780000${i.toString().padLeft(6, '0')}',
      publishedYear: 1900 + (i % 120),
    ),
  );

  // Every [everyNth] row has its title and its author in Devanagari, which
  // are pictures. The authors repeat (seven of them), so the cache has hits.
  List<CatalogueItem> mixedRows(int n, {int everyNth = 3}) => List.generate(
    n,
    (i) => CatalogueItem(
      title: i % everyNth == 0
          ? 'किताब संख्या $i जिसका नाम बहुत लंबा है और टूटता है'
          : 'Unique title number $i with some more words to wrap it',
      author: i % everyNth == 0 ? 'लेखक ${i % 7}' : 'Author $i',
      isbn: i % 5 == 0 ? null : '9780000${i.toString().padLeft(6, '0')}',
      publishedYear: 1900 + (i % 60),
      copyCount: 1 + (i % 3),
      publisher: i % 4 == 0 ? 'राजकमल प्रकाशन' : 'Penguin',
      language: i % everyNth == 0 ? 'हिन्दी' : 'English',
      location: 'Shelf ${i % 9}',
      sourceType: ItemSourceType.values[i % ItemSourceType.values.length],
      sourceDetail: i % 6 == 0 ? 'राम शर्मा' : 'City Books and Stationers',
      addedDate: 1700000000000 + i * 86400000,
    ),
  );

  /// Counts with `measure`, then really renders with the SAME arguments, and
  /// holds the count to the finished file's own number of objects.
  Future<({PdfSizeEstimate estimate, Uint8List pdf, int pages, int pictures})>
  countThenRender({
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    PdfLibraryRenderer renderer = const PdfLibraryRenderer(),
    String libraryName = 'Riverside Library',
    String? subtitle,
    bool fonts = true,
    Uint8List? logo,
    Uint8List? icon,
    int maxCachedTiles = PdfLibraryRenderer.defaultMaxCachedTiles,
  }) async {
    final estimate = await renderer.measure(
      libraryName: libraryName,
      subtitle: subtitle,
      books: books,
      columns: columns,
      footerAttribution: kPdfFooterAttribution,
      regularFonts: fonts ? regular : const [],
      boldFonts: fonts ? bold : const [],
      logoBytes: logo,
      footerIconBytes: icon,
      maxCachedTiles: maxCachedTiles,
    );
    final raster = CountingPdfRasterizer();
    var pages = 0;
    final pdf = await renderer.render(
      libraryName: libraryName,
      subtitle: subtitle,
      books: books,
      columns: columns,
      footerAttribution: kPdfFooterAttribution,
      regularFonts: fonts ? regular : const [],
      boldFonts: fonts ? bold : const [],
      logoBytes: logo,
      footerIconBytes: icon,
      textRasterizer: raster,
      onProgress: (p) => pages = p.pagesDone,
      maxCachedTiles: maxCachedTiles,
    );
    expect(
      estimate.objectsNeeded,
      countPdfStreamObjects(pdf),
      reason: 'the count before the run against the finished file',
    );
    expect(estimate.rowsTotal, books.length);
    return (
      estimate: estimate,
      pdf: pdf,
      pages: pages,
      pictures: raster.runs.length,
    );
  }

  group('the count equals the finished file', () {
    test('a Latin library: its pages, the two fonts, and no picture', () async {
      final made = await countThenRender(
        books: latinRows(300),
        columns: cols(),
      );
      expect(made.pictures, 0);
      expect(made.pages, greaterThan(5));
      // One object a page, two for each of the two fonts, one of the file.
      expect(made.estimate.objectsNeeded, made.pages + 4 + 1);
      expect(made.estimate.fits, isTrue);
      expect(made.estimate.rowsThatFit, 300);
    });

    test('a mixed library: two objects for each picture on top', () async {
      final made = await countThenRender(
        books: mixedRows(200),
        columns: cols(),
      );
      expect(made.pictures, greaterThan(60));
      expect(
        made.estimate.objectsNeeded,
        made.pages + 2 * made.pictures + 4 + 1,
      );
    });

    test('a library that is all pictures, with a logo and the footer '
        'icon', () async {
      final made = await countThenRender(
        books: mixedRows(120, everyNth: 1),
        columns: cols(),
        libraryName: 'मेरी लाइब्रेरी',
        logo: logoPng,
        icon: iconPng,
      );
      // The logo and the icon are PNG files: two objects each.
      expect(
        made.estimate.objectsNeeded,
        made.pages + 2 * made.pictures + 4 + 2 + 2 + 1,
      );
    });

    test('a JPEG logo is ONE object, and a file that is no picture '
        'none', () async {
      final jpeg = Uint8List.fromList(
        im.encodeJpg(im.Image(width: 8, height: 8)),
      );
      final made = await countThenRender(
        books: latinRows(5),
        columns: cols(),
        logo: jpeg,
        icon: notAPicture,
      );
      expect(made.estimate.objectsNeeded, made.pages + 4 + 1 + 1);
    });

    test('without fonts (the built-in one) the fonts cost nothing', () async {
      final made = await countThenRender(
        books: mixedRows(40),
        columns: cols(),
        fonts: false,
      );
      expect(made.estimate.objectsNeeded, made.pages + 2 * made.pictures + 1);
    });

    test('all fourteen columns, a subtitle in Devanagari, the two lines of '
        'the Source column', () async {
      await countThenRender(
        books: mixedRows(90),
        columns: allCols(),
        subtitle: 'राम शर्मा द्वारा दान',
        logo: logoPng,
      );
    });

    test('a list without rows', () async {
      final made = await countThenRender(
        books: const [],
        columns: cols(),
        libraryName: 'पुस्तकालय',
      );
      expect(made.estimate.rowsTotal, 0);
      expect(made.estimate.rowsThatFit, 0);
      expect(made.estimate.fits, isTrue);
    });

    test('a text that comes again after its key was forgotten is counted '
        'again, as it is made again (a small cache)', () async {
      // Seven authors in turn and a cache of two keys: an author's picture
      // is long forgotten when the author comes round again.
      final made = await countThenRender(
        books: mixedRows(60, everyNth: 1),
        columns: cols(),
        maxCachedTiles: 2,
      );
      final cached = await countThenRender(
        books: mixedRows(60, everyNth: 1),
        columns: cols(),
      );
      expect(
        made.pictures,
        greaterThan(cached.pictures),
        reason:
            'the small cache must have cost pictures, or this test does '
            'not reach the edge it is about',
      );
    });

    test('across the edge of the cache of 512 keys', () async {
      // 513 different titles in Devanagari fill the cache and push the first
      // one out; then the first title comes again and is made a second time.
      const rows = 513;
      final books = [
        for (var i = 0; i < rows; i++)
          CatalogueItem(title: 'किताब $i', author: 'Author'),
        const CatalogueItem(title: 'किताब 0', author: 'Author'),
      ];
      final made = await countThenRender(books: books, columns: cols());
      expect(made.pictures, rows + 1);
    });
  });

  group('the budget', () {
    // Twenty rows with one picture each, on one page.
    final books = [
      for (var i = 0; i < 20; i++)
        CatalogueItem(title: 'किताब $i', author: 'Author $i'),
    ];

    Future<PdfSizeEstimate> measureWith(int budget) =>
        PdfLibraryRenderer(maxStreamObjects: budget).measure(
          libraryName: 'Riverside Library',
          books: books,
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          regularFonts: regular,
          boldFonts: bold,
        );

    Future<int> objectsOfTheFirst(int rows) async {
      final pdf = await const PdfLibraryRenderer().render(
        libraryName: 'Riverside Library',
        books: books.sublist(0, rows),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        regularFonts: regular,
        boldFonts: bold,
        textRasterizer: CountingPdfRasterizer(),
      );
      return countPdfStreamObjects(pdf);
    }

    test('the renderer of the app has the budget of the app', () async {
      final estimate = await const PdfLibraryRenderer().measure(
        libraryName: 'Riverside Library',
        books: books,
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
      );
      expect(estimate.objectsAllowed, pdfStreamObjectBudget);
    });

    test('a list exactly at the budget fits whole', () async {
      final needed = await objectsOfTheFirst(20);
      // One page, the two fonts, twenty pictures, one of the file.
      expect(needed, 1 + 4 + 2 * 20 + 1);
      final estimate = await measureWith(needed);
      expect(estimate.objectsNeeded, needed);
      expect(estimate.objectsAllowed, needed);
      expect(estimate.fits, isTrue);
      expect(estimate.rowsThatFit, 20);
    });

    test('one object less: the list does not fit, and the count says how '
        'many of its rows do', () async {
      final needed = await objectsOfTheFirst(20);
      final estimate = await measureWith(needed - 1);
      expect(estimate.objectsNeeded, needed);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsTotal, 20);
      expect(estimate.rowsThatFit, 19);
    });

    test('the rows that are said to fit DO fit, and one more row does '
        'not', () async {
      for (final budget in [8, 15, 16, 31, 44]) {
        final estimate = await measureWith(budget);
        expect(estimate.fits, isFalse, reason: 'budget $budget');
        final fit = estimate.rowsThatFit;
        expect(
          await objectsOfTheFirst(fit),
          lessThanOrEqualTo(budget),
          reason: 'the first $fit rows at a budget of $budget',
        );
        expect(
          await objectsOfTheFirst(fit + 1),
          greaterThan(budget),
          reason: 'the first ${fit + 1} rows at a budget of $budget',
        );
      }
    });

    test('when not even the empty page fits, no row does', () async {
      final estimate = await measureWith(3);
      expect(estimate.fits, isFalse);
      expect(estimate.rowsThatFit, 0);
    });
  });

  group('the count is a pass over the rows like the drawing', () {
    test('a counting pass leaves its document without a page and without '
        'a picture of a text', () async {
      // The pass itself, on a document the test can look into afterwards.
      final doc = PdfDocument();
      final estimate =
          await const PdfLibraryPass(
            draw: false,
            maxStreamObjects: pdfStreamObjectBudget,
          ).run(
            doc,
            libraryName: 'मेरी लाइब्रेरी',
            books: mixedRows(120, everyNth: 1),
            columns: cols(),
            footerAttribution: kPdfFooterAttribution,
            maxCachedTiles: PdfLibraryRenderer.defaultMaxCachedTiles,
            regularFonts: regular,
            boldFonts: bold,
            logoBytes: logoPng,
          );
      // More than a hundred pictures were COUNTED ...
      expect(estimate.objectsNeeded, greaterThan(200));
      // ... and none of them is in the document, nor is any page.
      expect(doc.pdfPageList.pages, isEmpty);
      expect(doc.objects.whereType<PdfPage>(), isEmpty);
      // The logo is there (two objects), and nothing else that is a picture.
      expect(doc.objects.whereType<PdfImage>(), hasLength(2));
      // The two fonts, the logo, and the one object of the file.
      expect(pdfFixedStreamObjects(doc), 4 + 2 + 1);
    });

    test('a token cancelled before the call counts nothing, not even for a '
        'list without rows', () async {
      // Without rows only the check at the very start can stop the pass.
      final token = RenderCancelToken()..cancel();
      await expectLater(
        const PdfLibraryRenderer().measure(
          libraryName: 'Riverside Library',
          books: const [],
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          cancelToken: token,
        ),
        throwsA(isA<PdfRenderCancelled>()),
      );
    });

    test('it gives the event loop its turns, and Cancel stops it at the '
        'next row', () async {
      // The timer can only fire if the count lets the event loop run before
      // it has gone through all its rows.
      final token = RenderCancelToken();
      final timer = Timer(Duration.zero, token.cancel);
      addTearDown(timer.cancel);
      await expectLater(
        const PdfLibraryRenderer().measure(
          libraryName: 'Riverside Library',
          books: mixedRows(400),
          columns: cols(),
          footerAttribution: kPdfFooterAttribution,
          cancelToken: token,
        ),
        throwsA(isA<PdfRenderCancelled>()),
      );
    });

    test('a long list in Devanagari is counted without one picture being '
        'made', () async {
      // 5,000 rows, two pictures each: drawn, that would be 20,000 objects
      // with 64 KiB each. The count needs none of them.
      final estimate = await const PdfLibraryRenderer(maxStreamObjects: 4000)
          .measure(
            libraryName: 'पुस्तकालय',
            books: [
              for (var i = 0; i < 5000; i++)
                CatalogueItem(title: 'किताब $i', author: 'लेखक $i'),
            ],
            columns: cols(),
            footerAttribution: kPdfFooterAttribution,
            regularFonts: regular,
            boldFonts: bold,
          );
      expect(estimate.fits, isFalse);
      expect(estimate.rowsTotal, 5000);
      expect(estimate.objectsNeeded, greaterThan(20000));
      // About 4,000 objects at four a row, less the pages and the fonts.
      expect(estimate.rowsThatFit, inInclusiveRange(950, 1000));
    });
  });
}
