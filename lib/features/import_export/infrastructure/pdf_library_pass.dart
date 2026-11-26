/// One pass over the rows of a book list (infrastructure layer, AGENTS.md
/// §3.1; ADR 0033): the layout of the PDF catalogue, and, when asked, its
/// drawing.
///
/// The renderer (`pdf_library_renderer.dart`) runs this pass in one of two
/// ways:
///  - DRAWING (`draw: true`): pages are added to the document, texts are
///    written or embedded as pictures. This is the export itself.
///  - COUNTING (`draw: false`): the rows are laid out in exactly the same
///    way (the same wrapping, the same page breaks, the same questions to
///    the tile cache), but no page and no picture is made. It is quick and
///    needs little memory, and it answers how many objects the PDF will
///    have and how many rows fit (`pdf_object_count.dart`).
///
/// WHY ONE PASS FOR BOTH (beginner note): a count that is worked out in a
/// second place sooner or later disagrees with what is drawn, because
/// somebody changes one and forgets the other. Here there is one loop, and
/// drawing is something it does or leaves out. A test holds the count to
/// the finished file's own number of objects.
///
/// How the layout works, what is bounded and what is not: see the header of
/// `pdf_library_renderer.dart`, which this code was part of until 2026-11.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_column_layout.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_image_decode.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_object_count.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_tiles.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Lays a book list out on pages and, when [draw] is set, draws it.
class PdfLibraryPass {
  /// Creates a pass. With [draw] it fills the document it is run on; without,
  /// it only counts. [maxStreamObjects] is the budget the count is held
  /// against (`pdfStreamObjectBudget` in the app).
  const PdfLibraryPass({required this.draw, required this.maxStreamObjects});

  /// Whether pages and pictures are really made.
  final bool draw;

  /// How many stream objects the document may have.
  final int maxStreamObjects;

  // A4 at 72dpi, in points. SHORT = portrait width / landscape height.
  /// Portrait page width / landscape page height (A4 short side, points).
  static const double pageShort = 595;

  /// Portrait page height / landscape page width (A4 long side, points).
  static const double pageLong = 842;

  /// Page margin on all sides (points).
  static const double margin = 36;

  /// Body/row text size (points).
  static const double bodyText = 12;

  /// Footer text size (points).
  static const double footerText = 9;

  /// Library-name title text size (points).
  static const double titleText = 20;

  /// Column-header text size (points).
  static const double headerText = 12;

  /// Row line height for 12pt text (points).
  static const double lineHeight = 17;

  /// Square box the header logo is fitted into (points).
  static const double headerLogo = 44;

  /// Leading "#" serial-number gutter width (points).
  static const double serialWidth = 30;

  /// Header label for the serial-number gutter.
  static const String serialHeader = '#';

  /// Footer band height (points).
  static const double footerHeight = 30;

  /// Footer app-icon size (points).
  static const double footerIcon = 22;

  /// Beyond this many columns, switch portrait → landscape.
  static const int landscapeColumnThreshold = 6;

  /// Rows between explicit event-loop yields (see the library doc).
  static const int _yieldEveryRows = 20;

  static const PdfColor _footerGrey = PdfColor.fromInt(0xFF888888);
  static const PdfColor _black = PdfColors.black;

  /// Runs the pass over [books] on [doc] and answers what the document
  /// holds, or would hold, at its end.
  ///
  /// [doc] is a fresh document. A drawing pass leaves the finished pages in
  /// it. A counting pass puts only the fonts, the logo and the icon into it
  /// (the fonts are asked which texts they can write, and all three are
  /// counted from the real thing); the caller throws that document away.
  ///
  /// The arguments are those of `LibraryPdfRenderer.render`. A counting pass
  /// needs no [textRasterizer] and never asks one.
  Future<PdfSizeEstimate> run(
    PdfDocument doc, {
    required String libraryName,
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    required int maxCachedTiles,
    String? subtitle,
    PdfFontBundle regularFonts = const [],
    PdfFontBundle boldFonts = const [],
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    PdfTextRasterizer? textRasterizer,
    PdfRenderProgressListener? onProgress,
    RenderCancelToken? cancelToken,
  }) async {
    // A token cancelled before we start does nothing at all.
    cancelToken?.throwIfCancelled();

    // Per-string font resolvers: pick the first bundled font that can encode a
    // string's runes (Latin base + Indic fallbacks). Falls back to Helvetica
    // when no TTFs are supplied (Latin-only callers / tests).
    final regular = PdfFontResolver.fromBytes(doc, regularFonts);
    final bold = PdfFontResolver.fromBytes(doc, boldFonts);

    // Each text is either written as real text with these fonts, or (when it
    // needs shaping, as Devanagari does, or has a character the font lacks)
    // drawn by Flutter's engine and embedded as a picture. `PdfTextTiles`
    // decides: a null tile means "real text, use drawString". Tiles are made
    // per ROW (below) through a bounded cache. A text that needs a picture
    // and cannot get one throws there and ends the render. A counting pass
    // takes the same decisions and makes no picture.
    final tiles = PdfTextTiles(
      doc,
      textRasterizer,
      maxCachedTiles,
      regular: regular,
      bold: bold,
      makePictures: draw,
    );

    // Decode the bitmaps once (drawImage can reuse the same XObject per page).
    final logo = tryDecodePdfImage(doc, logoBytes);
    final footerIco = tryDecodePdfImage(doc, footerIconBytes);

    // The count starts from what the document holds NOW (its fonts, the logo,
    // the icon). From here on only pages and text pictures are added, and
    // both passes number those in the same places (`report`, below).
    final count = PdfObjectCount(
      fixedObjects: pdfFixedStreamObjects(doc),
      maxObjects: maxStreamObjects,
    );

    // Landscape once the selection gets wide, so columns keep breathing room.
    final landscape = columns.length > landscapeColumnThreshold;
    final pageW = landscape ? pageLong : pageShort;
    final pageH = landscape ? pageShort : pageLong;

    const contentLeft = margin;
    final contentRight = pageW - margin;
    final footerTop = pageH - margin - footerHeight;
    final rowBottomLimit = footerTop - 6;

    // Fixed leading serial-number gutter.
    const serialX = contentLeft;
    const columnsLeft = contentLeft + serialWidth;
    final columnsWidth = contentRight - columnsLeft;

    // Each column's x-offset and width, from its weight.
    final cols = layOutPdfColumns(
      columns,
      left: columnsLeft,
      width: columnsWidth,
    );

    // --- per-page drawing helpers (operate on a top-down `y`) ------------

    // Convert a top-down y (0 = page top) to a PDF baseline y.
    double ty(double y) => pageH - y;

    // Draws one run. [tile] is the pre-rasterized shaped image for exactly
    // this string/size/weight (or null → `drawString`). Passing the tile in
    // explicitly (rather than looking it up) means a row is always drawn
    // with the tiles it just produced, whatever the cache did meanwhile.
    //
    // Every draw helper takes a graphics that is NULL in a counting pass and
    // then draws nothing; whatever it works out about the layout (where the
    // table starts, how tall the header is) it works out all the same.
    void drawText(
      PdfGraphics? g,
      String s,
      double x,
      double y,
      PdfFontResolver font,
      double size,
      PdfColor color,
      PdfTextTile? tile,
    ) {
      if (g == null || s.isEmpty) return;
      if (tile != null) {
        // Tile top in top-down space sits `baselinePt` above baseline `y`;
        // drawImage anchors bottom-left, so pass the tile's bottom edge.
        final topDownTop = y - tile.baselinePt;
        final bottomY = ty(topDownTop + tile.heightPt);
        g.drawImage(tile.image, x, bottomY, tile.widthPt, tile.heightPt);
        return;
      }
      // Resolve the font per string by glyph coverage (mixed-script support).
      g
        ..setColor(color)
        ..drawString(font.fontFor(s), size, s, x, ty(y));
    }

    // --- page chrome: rasterized ONCE, held for the whole render ----------
    // These few strings repeat on every page, so they are not part of the
    // bounded row cache (they would always be the hottest entries anyway).

    final titleTile = await tiles.pinned(
      libraryName,
      titleText,
      _black,
      bold: true,
    );
    // A blank subtitle is "no subtitle": nothing drawn, nothing reserved.
    final subtitleText = subtitle?.trim() ?? '';
    final subtitleTile = subtitleText.isEmpty
        ? null
        : await tiles.pinned(subtitleText, bodyText, _black, bold: false);
    final serialHeaderTile = await tiles.pinned(
      serialHeader,
      headerText,
      _black,
      bold: true,
    );
    final colHeaderTexts = [
      for (final col in cols)
        ellipsizePdfHeader(col.print.header, pdfCharsThatFit(col.width)),
    ];
    final colHeaderTiles = <PdfTextTile?>[
      for (final text in colHeaderTexts)
        await tiles.pinned(text, headerText, _black, bold: true),
    ];
    final footerTile = await tiles.pinned(
      footerAttribution,
      footerText,
      _footerGrey,
      bold: false,
    );

    void drawFooter(PdfGraphics? g) {
      if (g == null) return;
      // Divider rule separating the page body from the footer.
      final ruleY = footerTop;
      g
        ..setStrokeColor(_footerGrey)
        ..setLineWidth(0.7)
        ..drawLine(contentLeft, ty(ruleY), contentRight, ty(ruleY))
        ..strokePath();

      const iconSize = footerIcon;
      // Top-down top edge of the icon box, vertically centred in the footer.
      final iconTop = ruleY + (footerHeight - iconSize) / 2 + 2;
      var textX = contentLeft;
      if (footerIco != null) {
        // drawImage anchors at the bottom-left in PDF space; pass the bottom y.
        g.drawImage(
          footerIco,
          contentLeft,
          ty(iconTop + iconSize),
          iconSize,
          iconSize,
        );
        textX = contentLeft + iconSize + 8;
      }
      // Vertically centre the footer text against the icon.
      final textY = iconTop + iconSize / 2 + footerText / 2 - 1;
      drawText(
        g,
        footerAttribution,
        textX,
        textY,
        regular,
        footerText,
        _footerGrey,
        footerTile,
      );
    }

    double drawHeader(PdfGraphics? g) {
      var top = margin + 4;
      var nameX = contentLeft;
      if (logo != null) {
        // Fit the logo inside a headerLogo square box preserving aspect ratio.
        const box = headerLogo;
        final scale = (box / logo.width) < (box / logo.height)
            ? (box / logo.width)
            : (box / logo.height);
        final w = logo.width * scale;
        final h = logo.height * scale;
        final topPad = margin + (box - h) / 2;
        g?.drawImage(logo, contentLeft, ty(topPad + h), w, h);
        nameX = contentLeft + box + 12;
        top = margin + box * 0.62; // vertically align name to logo
      }
      drawText(g, libraryName, nameX, top, bold, titleText, _black, titleTile);
      const logoOrText = headerLogo > 22 ? headerLogo : 22.0;
      var bottom = margin + logoOrText + 16;
      if (subtitleText.isNotEmpty) {
        // One body line under the name, aligned with it (so it sits right of
        // the logo too); the table starts one line lower to make room.
        drawText(
          g,
          subtitleText,
          nameX,
          top + lineHeight,
          regular,
          bodyText,
          _black,
          subtitleTile,
        );
        bottom += lineHeight;
      }
      return bottom;
    }

    double drawColumnHeaders(PdfGraphics? g, double startY) {
      drawText(
        g,
        serialHeader,
        serialX,
        startY,
        bold,
        headerText,
        _black,
        serialHeaderTile,
      );
      for (var i = 0; i < cols.length; i++) {
        drawText(
          g,
          colHeaderTexts[i],
          cols[i].x,
          startY,
          bold,
          headerText,
          _black,
          colHeaderTiles[i],
        );
      }
      // Underline rule beneath the headers.
      final ruleY = startY + 4;
      g
        ?..setStrokeColor(_black)
        ..setLineWidth(1)
        ..drawLine(contentLeft, ty(ruleY), contentRight, ty(ruleY))
        ..strokePath();
      return startY + lineHeight + 2;
    }

    // --- pagination loop --------------------------------------------------

    // The pdf package numbers pages implicitly by insertion order, so we just
    // append a new PdfPage when a row overflows the printable area. A
    // counting pass makes no page: it only numbers them (`pages`).
    PdfGraphics? newPage() => draw
        ? PdfPage(doc, pageFormat: PdfPageFormat(pageW, pageH)).getGraphics()
        : null;

    var pages = 1;
    var g = newPage();
    var y = drawHeader(g);
    y = drawColumnHeaders(g, y);
    drawFooter(g);

    // After every row: the count notes what the document holds by now, and
    // the caller hears how far the pass is.
    void report(int rowsDone) {
      count.rowsDone(rowsDone, pages: pages, pictures: tiles.picturesMade);
      onProgress?.call(
        PdfRenderProgress(
          rowsDone: rowsDone,
          rowsTotal: books.length,
          pagesDone: pages,
          cachedTiles: tiles.cachedCount,
        ),
      );
    }

    report(0);

    if (books.isEmpty) {
      final emptyTile = await tiles.row('(empty)', bodyText, _black);
      drawText(
        g,
        '(empty)',
        contentLeft,
        y,
        regular,
        bodyText,
        _black,
        emptyTile,
      );
    }

    var serial = 0;
    for (final book in books) {
      // Stop at a row boundary when asked; nothing is returned (D1-a).
      cancelToken?.throwIfCancelled();
      serial += 1;

      // Pre-compute the wrapped cell lines for this row to know its height.
      final cellLines = cols.map((col) {
        final limit = pdfCharsThatFit(col.width);
        final logical = col.print.cell(book);
        return wrapCell(logical, limit, col.print.wrapLines);
      }).toList();
      final maxLines = cellLines.fold<int>(
        1,
        (m, l) => l.length > m ? l.length : m,
      );
      final rowLines = maxLines < 1 ? 1 : maxLines;
      final rowHeight = rowLines * lineHeight;

      // Rasterize THIS row's runs now (N10-e): the serial and every wrapped
      // cell line, in draw order. Nothing beyond this row is touched.
      final serialText = '$serial';
      final serialTile = await tiles.row(serialText, bodyText, _black);
      final lineTiles = <List<PdfTextTile?>>[
        for (final lines in cellLines)
          <PdfTextTile?>[
            for (final line in lines) await tiles.row(line, bodyText, _black),
          ],
      ];

      if (y + rowHeight > rowBottomLimit) {
        pages += 1;
        g = newPage();
        y = drawHeader(g);
        y = drawColumnHeaders(g, y);
        drawFooter(g);
      }

      // Serial number, drawn on the row's first line.
      drawText(
        g,
        serialText,
        serialX,
        y,
        regular,
        bodyText,
        _black,
        serialTile,
      );
      for (var i = 0; i < cols.length; i++) {
        final lines = cellLines[i];
        for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
          drawText(
            g,
            lines[lineIdx],
            cols[i].x,
            y + lineIdx * lineHeight,
            regular,
            bodyText,
            _black,
            lineTiles[i][lineIdx],
          );
        }
      }
      y += rowHeight;

      report(serial);
      // Give the event loop a turn so the progress just reported can paint
      // (a microtask-only await would not let the frame scheduler run).
      if (serial % _yieldEveryRows == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return count.estimate(
      rowsTotal: books.length,
      pages: pages,
      pictures: tiles.picturesMade,
    );
  }
}
