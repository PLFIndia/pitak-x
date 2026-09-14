import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart'
    show defaultPdfLabels, kPdfFooterAttribution;
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// A 1x1 transparent PNG — the smallest image `PdfImage.file` can decode, so
/// the fake tiles below take the REAL embed path (decode + XObject) without
/// needing `dart:ui`.
final _onePxPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Counts every text run the renderer asks for and remembers the order, so a
/// test can tell WHEN a row was rasterized (N10-e: per row, not all up front)
/// and how many rows a cancelled render touched. Optionally yields to the
/// event loop per call, like the real `dart:ui` rasterizer does.
class _CountingRasterizer implements PdfTextRasterizer {
  _CountingRasterizer({this.yieldPerCall = false});

  final bool yieldPerCall;
  final List<String> runs = [];

  @override
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  }) async {
    runs.add(text);
    if (yieldPerCall) await Future<void>.delayed(Duration.zero);
    return RasterizedText(
      pngBytes: _onePxPng,
      widthPt: text.length * 6.0,
      heightPt: 14,
      baselinePt: 11,
    );
  }
}

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
      const Book(title: 'A Book', author: 'An Author', copyCount: 2),
      const Book(title: 'Another', isbn: '978-1', publishedYear: 2020),
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

  test('renders Devanagari (Hindi) titles without throwing', () async {
    // This is the exact failure case that crashed Helvetica (Latin-1 only).
    final books = [
      const Book(title: 'भारत: गांधी के बाद', author: 'Ramachandra Guha'),
      const Book(title: 'गोदान', author: 'प्रेमचंद'),
    ];
    final bytes = await renderer.render(
      libraryName: 'मेरी लाइब्रेरी',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('paginates a large library without throwing', () async {
    final books = List.generate(
      200,
      (i) => Book(title: 'Book number $i', author: 'Author $i'),
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

  test('a bad logo/icon is skipped, not fatal', () async {
    final bytes = await renderer.render(
      libraryName: 'Lib',
      books: const [Book(title: 'X')],
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      logoBytes: Uint8List.fromList([1, 2, 3, 4]),
      footerIconBytes: Uint8List.fromList([5, 6, 7, 8]),
    );
    expectValidPdf(bytes);
  });

  group('N10-e — bounded tiles, progress, cancel (shaped-image mode)', () {
    // Every title/author/ISBN is unique so nothing dedups: the tile count is
    // the honest measure of what the renderer holds on to.
    List<Book> uniqueRows(int n) => List.generate(
      n,
      (i) => Book(
        title: 'Unique title number $i with some words',
        author: 'Author $i',
        isbn: '9780000${i.toString().padLeft(6, '0')}',
        publishedYear: 1900 + (i % 120),
        copyCount: 1 + (i % 3),
      ),
    );

    test('the tile cache never holds more than the bound', () async {
      final raster = _CountingRasterizer();
      final seen = <PdfRenderProgress>[];
      const bound = 64;
      final bytes = await renderer.render(
        libraryName: 'Big',
        books: uniqueRows(2000),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: raster,
        onProgress: seen.add,
        maxCachedTiles: bound,
      );
      expectValidPdf(bytes);
      // 2000 rows × (serial + title + author + isbn) is ≥ 8,000 distinct
      // runs — two orders of magnitude over the bound — yet the cache must
      // still top out at the bound.
      expect(raster.runs.toSet().length, greaterThan(bound * 100));
      final peak = seen
          .map((p) => p.cachedTiles)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, lessThanOrEqualTo(bound), reason: 'peak cache $peak');
    });

    test('the default bound is 512 tiles', () {
      expect(PdfLibraryRenderer.defaultMaxCachedTiles, 512);
    });

    test('rows are rasterized as they are drawn, not all up front', () async {
      final raster = _CountingRasterizer();
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
      // When row 1 was reported done, the last row's ISBN (a single run —
      // ISBNs never wrap) must NOT have been rasterized yet. HEAD
      // pre-rasterized every row before drawing any.
      final runsWhenRow1Done = firstRowSeenAt[1]!;
      final lastIsbnIndex = raster.runs.indexOf('9780000000119');
      expect(lastIsbnIndex, isNot(-1));
      expect(lastIsbnIndex, greaterThanOrEqualTo(runsWhenRow1Done));
    });

    test('progress is monotonic, starts at 0 and ends at rowsTotal', () async {
      final seen = <PdfRenderProgress>[];
      await renderer.render(
        libraryName: 'Progress',
        books: uniqueRows(150),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: _CountingRasterizer(),
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
        books: uniqueRows(10),
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
      final raster = _CountingRasterizer();
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
      // runs; row 12 must not have been (ISBNs are single, unwrapped runs).
      expect(raster.runs, contains(books[9].isbn));
      expect(raster.runs, isNot(contains(books[11].isbn)));
      expect(raster.runs, isNot(contains(books.last.isbn)));
    });

    test('a token cancelled before the call renders nothing', () async {
      final raster = _CountingRasterizer();
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
      // before a 300-row render finishes.
      final sw = Stopwatch()..start();
      var firedAt = -1;
      final timer = Timer(const Duration(milliseconds: 1), () {
        firedAt = sw.elapsedMilliseconds;
      });
      await renderer.render(
        libraryName: 'Yield',
        books: uniqueRows(300),
        columns: cols(),
        footerAttribution: kPdfFooterAttribution,
        textRasterizer: _CountingRasterizer(yieldPerCall: true),
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
  });
}
