/// Paginated PDF book-list renderer (infrastructure layer, AGENTS.md §3.1;
/// ADR 0033).
///
/// Rendered with the pure-Dart `pdf` package. This file is the port's two
/// methods: `measure` COUNTS what a PDF of a list would hold, `render` makes
/// it. Both run the same pass over the rows (`pdf_library_pass.dart`, which
/// holds the layout this header describes); `render` then writes the file.
///
/// Features:
///  - User-selectable columns (resolved by [resolvePrintColumns]); widths
///    distributed by per-column weight across the printable area.
///  - Header: optional library logo drawn beside the library name.
///  - Footer on every page: the Pitak app icon + attribution line.
///  - Page orientation auto-switches to landscape when many columns are chosen.
///  - Multi-line cells (the Source/Source-detail merge renders two lines).
///  - A leading serial-number gutter ("#" / 1, 2, 3…).
///
/// COORDINATE NOTE: Android Canvas has its origin top-left with Y growing
/// downward; the `pdf` package uses PDF user space — origin bottom-left, Y
/// growing UPWARD. To keep the layout maths top-down (as on a canvas),
/// all `y` values of the pass are TOP-DOWN (0 = top of page), and are
/// converted to PDF space only at draw time via `ty(y) = pageH - y`. Text is
/// drawn from its baseline in both APIs, so a top-down baseline `y` maps to
/// `pageH - y`.
///
/// MEMORY / RESPONSIVENESS (review finding N10-e: the PDF used to
/// pre-rasterize and retain every text run of the catalogue): a text that
/// needs shaping is rasterized by the platform text engine, which only works
/// on the UI isolate (which text that is: `pdf_text_tiles.dart`; Latin
/// letters and digits are written as real text and cost no picture). The
/// renderer therefore
///  - rasterizes each ROW right before drawing it (never the whole catalogue
///    up front), so the wait is spread over the run and can be cancelled;
///  - keeps the fixed page chrome (title, column headers, footer) as a
///    handful of tiles for the whole render, and puts ROW tiles through a
///    small least-recently-used cache (`defaultMaxCachedTiles` entries) that
///    drops the PNG bytes as soon as the tile is embedded — so repeated
///    short cells (years, quantities) are reused and one-off titles are let
///    go straight after their row;
///  - reports progress once per row and checks the cancel token at every
///    row boundary; a cancelled render throws `PdfRenderCancelled` and
///    produces no bytes (decision D1-a: no partial catalogue);
///  - yields to the event loop every `_yieldEveryRows` rows in ALL modes so
///    the screen can repaint the progress bar even when no rasterizer (and
///    hence no engine await) is involved.
///
/// What this does NOT bound: the `pdf` package keeps every embedded picture
/// as objects of the document until the file is written (that is how pages
/// point at them), so a PDF with shaped text still grows with its pictures,
/// and a document can hold only some thousand of them on any phone. That is
/// why a list is counted first and refused when it would not fit
/// (`measure`; `pdf_object_count.dart` says what is counted and why), and
/// why the file is written from the document itself and not with the
/// package's `save()` (see the comment in `render`).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_pass.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_object_count.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Renders a book list to a paginated PDF and returns the encoded bytes.
class PdfLibraryRenderer implements LibraryPdfRenderer {
  /// Creates the renderer. [maxStreamObjects] is how many stream objects one
  /// PDF may have (see `pdf_object_count.dart` for what that is and why it
  /// is a count); the app takes the default, a test hands a small number.
  const PdfLibraryRenderer({this.maxStreamObjects = pdfStreamObjectBudget});

  /// Default bound on ROW text tiles held at once (N10-e, decision D5-b).
  /// The widest layout (14 landscape columns) needs roughly 400 tiles per
  /// page, so 512 keeps one page's working set plus repeated short cells
  /// without thrashing; each entry is a decoded-image handle plus three
  /// doubles, so the cache itself stays tiny.
  static const int defaultMaxCachedTiles = 512;

  /// The budget [measure] holds a list against.
  final int maxStreamObjects;

  /// Counts what [render] would make of the same arguments, without making
  /// it: see [LibraryPdfRenderer.measure].
  ///
  /// The same pass as [render] goes over the rows (`PdfLibraryPass`), with
  /// its drawing left out, on a document of its own that is thrown away.
  @override
  Future<PdfSizeEstimate> measure({
    required String libraryName,
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    String? subtitle,
    PdfFontBundle regularFonts = const [],
    PdfFontBundle boldFonts = const [],
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    RenderCancelToken? cancelToken,
    int maxCachedTiles = defaultMaxCachedTiles,
  }) => PdfLibraryPass(draw: false, maxStreamObjects: maxStreamObjects).run(
    PdfDocument(),
    libraryName: libraryName,
    books: books,
    columns: columns,
    footerAttribution: footerAttribution,
    maxCachedTiles: maxCachedTiles,
    subtitle: subtitle,
    regularFonts: regularFonts,
    boldFonts: boldFonts,
    logoBytes: logoBytes,
    footerIconBytes: footerIconBytes,
    cancelToken: cancelToken,
  );

  /// Renders [books] to a PDF.
  ///
  /// [libraryName] is the page-header title. [subtitle] (optional, e.g.
  /// "Donated by Ram Sharma") is drawn under it in body-size regular text and
  /// pushes the table down by one [PdfLibraryPass.lineHeight]. [logoBytes] is
  /// an optional library logo (decoded PNG/JPEG bytes) drawn left of the name.
  /// [footerIconBytes] is the Pitak app icon for the footer.
  /// [footerAttribution] is the footer line. [columns] are the resolved
  /// printable columns.
  ///
  /// [regularFonts]/[boldFonts] are the TTF fonts real text is written with
  /// (when empty: Helvetica, Latin-1 only; see `PdfFontResolver`). Which text
  /// is real text and which a picture: see [LibraryPdfRenderer.render].
  ///
  /// [onProgress], [cancelToken] and [maxCachedTiles]: see the library doc
  /// and [LibraryPdfRenderer.render].
  @override
  Future<Uint8List> render({
    required String libraryName,
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    String? subtitle,
    PdfFontBundle regularFonts = const [],
    PdfFontBundle boldFonts = const [],
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    PdfTextRasterizer? textRasterizer,
    PdfRenderProgressListener? onProgress,
    RenderCancelToken? cancelToken,
    int maxCachedTiles = defaultMaxCachedTiles,
  }) async {
    final doc = PdfDocument();
    await PdfLibraryPass(draw: true, maxStreamObjects: maxStreamObjects).run(
      doc,
      libraryName: libraryName,
      books: books,
      columns: columns,
      footerAttribution: footerAttribution,
      maxCachedTiles: maxCachedTiles,
      subtitle: subtitle,
      regularFonts: regularFonts,
      boldFonts: boldFonts,
      logoBytes: logoBytes,
      footerIconBytes: footerIconBytes,
      textRasterizer: textRasterizer,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    // The file is written HERE, from the document itself, and not with the
    // package's `save()`: that one hands its work to another isolate, and to
    // get there the whole document is copied first, so every one of its
    // 64 KiB buffers would be needed a second time (`pdf_object_count.dart`
    // says why there are only so many). `enableEventLoopBalancing` makes the
    // package pause between the objects it writes, so the progress row keeps
    // moving and a tap is heard. `pdf_document_write_test.dart` keeps
    // `save()` out.
    final output = PdfStream();
    await doc.write(output, enableEventLoopBalancing: true);
    return output.output();
  }
}
