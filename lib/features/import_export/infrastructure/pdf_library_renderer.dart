/// Paginated PDF book-list renderer (infrastructure layer, AGENTS.md §3.1).
///
/// Faithful port of Kotlin `data/export/PdfLibraryRenderer.kt`, rendered with
/// the pure-Dart `pdf` package instead of `android.graphics.pdf.PdfDocument`.
///
/// Features (Kotlin parity):
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
/// growing UPWARD. To keep this a line-for-line port of the Kotlin top-down
/// layout maths, all `y` values below are TOP-DOWN (0 = top of page), and we
/// convert to PDF space only at draw time via `_ty(y) = pageH - y`. Text is
/// drawn from its baseline in both APIs, so a top-down baseline `y` maps to
/// `pageH - y`.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Renders a book list to a paginated PDF and returns the encoded bytes.
class PdfLibraryRenderer {
  /// Creates the renderer.
  const PdfLibraryRenderer();

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

  static const PdfColor _footerGrey = PdfColor.fromInt(0xFF888888);
  static const PdfColor _black = PdfColors.black;

  /// Renders [books] to a PDF.
  ///
  /// [libraryName] is the page-header title. [logoBytes] is an optional library
  /// logo (decoded PNG/JPEG bytes) drawn left of the name. [footerIconBytes] is
  /// the Pitak app icon for the footer. [footerAttribution] is the footer line.
  /// [columns] are the resolved printable columns.
  ///
  /// [regularFonts]/[boldFonts] are ordered TTF byte bundles (base/Latin first,
  /// then script fallbacks) used to render text the built-in Latin-1 fonts
  /// cannot. When empty, Helvetica is used (Latin-only); see [PdfFontResolver].
  Future<Uint8List> render({
    required String libraryName,
    required List<Book> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    PdfFontBundle regularFonts = const [],
    PdfFontBundle boldFonts = const [],
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    PdfTextRasterizer? textRasterizer,
  }) async {
    final doc = PdfDocument();

    // When a rasterizer is supplied, text is shaped by Flutter's engine
    // (HarfBuzz) and embedded as images so complex scripts (Devanagari joins
    // / half-letters, matra reordering) render correctly — `drawString` cannot
    // shape them. We pre-rasterize every run into a cache so the synchronous
    // pagination loop can look tiles up by (text, size, bold). A cached null
    // means "skip / fall back". When no rasterizer is supplied (Latin-only
    // callers, pure tests) we keep the original `drawString` path.
    final tileCache = <String, RasterizedText?>{};
    String tileKey(String s, double size, PdfColor c, {required bool bold}) =>
        '${bold ? 'B' : 'R'}|$size|${c.toInt()}|$s';
    Future<void> cacheTile(
      String s,
      double size,
      PdfColor color, {
      required bool bold,
    }) async {
      if (textRasterizer == null || s.isEmpty) return;
      final key = tileKey(s, size, color, bold: bold);
      if (tileCache.containsKey(key)) return;
      tileCache[key] = await textRasterizer.raster(
        s,
        fontSize: size,
        bold: bold,
        colorArgb: color.toInt() | 0xFF000000,
      );
    }

    // Per-string font resolvers: pick the first bundled font that can encode a
    // string's runes (Latin base + Indic fallbacks). Falls back to Helvetica
    // when no TTFs are supplied (Latin-only callers / tests).
    final regular = PdfFontResolver.fromBytes(doc, regularFonts);
    final bold = PdfFontResolver.fromBytes(doc, boldFonts);

    // Decode the bitmaps once (drawImage can reuse the same XObject per page).
    final logo = _tryDecode(doc, logoBytes);
    final footerIco = _tryDecode(doc, footerIconBytes);

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

    // Resolve each column's x-offset and pixel width from its weight.
    final totalWeight = columns
        .fold<double>(0, (a, c) => a + c.weight)
        .clamp(1, double.infinity);
    final cols = <_Col>[];
    var cx = columnsLeft;
    for (final c in columns) {
      final w = columnsWidth * (c.weight / totalWeight);
      cols.add(_Col(c, cx, w));
      cx += w;
    }

    // Approx chars that fit a column width at the row text size. At 12pt, an
    // average Helvetica glyph is ~6.6pt wide. (Kotlin uses the same constant.)
    int maxChars(double width) {
      final n = (width / 6.6).floor();
      return n < 3 ? 3 : n;
    }

    // --- per-page drawing helpers (operate on a top-down `y`) ------------

    // Convert a top-down y (0 = page top) to a PDF baseline y.
    double ty(double y) => pageH - y;

    // Per-document cache of embedded text-tile XObjects (decode each PNG once).
    final tileImages = <String, PdfImage?>{};

    void drawText(
      PdfGraphics g,
      String s,
      double x,
      double y,
      PdfFontResolver font,
      double size,
      PdfColor color,
    ) {
      if (s.isEmpty) return;
      // Shaped-image path: embed the pre-rasterized tile at baseline `y`.
      if (textRasterizer != null) {
        final key = tileKey(s, size, color, bold: identical(font, bold));
        final tile = tileCache[key];
        if (tile != null) {
          final img = tileImages.putIfAbsent(
            key,
            () => _tryDecode(doc, tile.pngBytes),
          );
          if (img != null) {
            // Tile top in top-down space sits `baselinePt` above baseline `y`;
            // drawImage anchors bottom-left, so pass the tile's bottom edge.
            final topDownTop = y - tile.baselinePt;
            final bottomY = ty(topDownTop + tile.heightPt);
            g.drawImage(img, x, bottomY, tile.widthPt, tile.heightPt);
            return;
          }
        }
        // Fall through to drawString if this run had no usable tile.
      }
      // Resolve the font per string by glyph coverage (mixed-script support).
      g
        ..setColor(color)
        ..drawString(font.fontFor(s), size, s, x, ty(y));
    }

    void drawFooter(PdfGraphics g) {
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
      );
    }

    double drawHeader(PdfGraphics g) {
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
        g.drawImage(logo, contentLeft, ty(topPad + h), w, h);
        nameX = contentLeft + box + 12;
        top = margin + box * 0.62; // vertically align name to logo
      }
      drawText(g, libraryName, nameX, top, bold, titleText, _black);
      const logoOrText = headerLogo > 22 ? headerLogo : 22.0;
      return margin + logoOrText + 16;
    }

    double drawColumnHeaders(PdfGraphics g, double startY) {
      drawText(g, serialHeader, serialX, startY, bold, headerText, _black);
      for (final col in cols) {
        drawText(
          g,
          _ellipsize(col.print.header, maxChars(col.width)),
          col.x,
          startY,
          bold,
          headerText,
          _black,
        );
      }
      // Underline rule beneath the headers.
      final ruleY = startY + 4;
      g
        ..setStrokeColor(_black)
        ..setLineWidth(1)
        ..drawLine(contentLeft, ty(ruleY), contentRight, ty(ruleY))
        ..strokePath();
      return startY + lineHeight + 2;
    }

    // --- pre-rasterize every text run (shaped-image mode only) ------------

    if (textRasterizer != null) {
      await cacheTile(libraryName, titleText, _black, bold: true);
      await cacheTile(serialHeader, headerText, _black, bold: true);
      for (final col in cols) {
        await cacheTile(
          _ellipsize(col.print.header, maxChars(col.width)),
          headerText,
          _black,
          bold: true,
        );
      }
      await cacheTile(footerAttribution, footerText, _footerGrey, bold: false);
      await cacheTile('(empty)', bodyText, _black, bold: false);
      var serialNo = 0;
      for (final book in books) {
        serialNo += 1;
        await cacheTile('$serialNo', bodyText, _black, bold: false);
        for (final col in cols) {
          final limit = maxChars(col.width);
          final logical = col.print.cell(book);
          for (final line in wrapCell(logical, limit, col.print.wrapLines)) {
            await cacheTile(line, bodyText, _black, bold: false);
          }
        }
      }
    }

    // --- pagination loop --------------------------------------------------

    // The pdf package numbers pages implicitly by insertion order, so we just
    // append a new PdfPage when a row overflows the printable area.
    var page = PdfPage(doc, pageFormat: PdfPageFormat(pageW, pageH));
    var g = page.getGraphics();
    var y = drawHeader(g);
    y = drawColumnHeaders(g, y);
    drawFooter(g);

    if (books.isEmpty) {
      drawText(g, '(empty)', contentLeft, y, regular, bodyText, _black);
    }

    var serial = 0;
    for (final book in books) {
      serial += 1;
      // Pre-compute the wrapped cell lines for this row to know its height.
      final cellLines = cols.map((col) {
        final limit = maxChars(col.width);
        final logical = col.print.cell(book);
        return wrapCell(logical, limit, col.print.wrapLines);
      }).toList();
      final maxLines = cellLines.fold<int>(
        1,
        (m, l) => l.length > m ? l.length : m,
      );
      final rowLines = maxLines < 1 ? 1 : maxLines;
      final rowHeight = rowLines * lineHeight;

      if (y + rowHeight > rowBottomLimit) {
        page = PdfPage(doc, pageFormat: PdfPageFormat(pageW, pageH));
        g = page.getGraphics();
        y = drawHeader(g);
        y = drawColumnHeaders(g, y);
        drawFooter(g);
      }

      // Serial number, drawn on the row's first line.
      drawText(g, '$serial', serialX, y, regular, bodyText, _black);
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
          );
        }
      }
      y += rowHeight;
    }

    return doc.save();
  }

  /// Hard truncate over-long header cells so columns don't overlap.
  static String _ellipsize(String s, int max) {
    if (s.length <= max) return s;
    final keep = (max - 1) < 1 ? 1 : (max - 1);
    return '${s.substring(0, keep)}…';
  }

  static PdfImage? _tryDecode(PdfDocument doc, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return PdfImage.file(doc, bytes: bytes);
    } on Object {
      // A bad logo/icon must never abort the export; just skip it.
      return null;
    }
  }
}

/// A resolved column with its laid-out x-offset and pixel width.
class _Col {
  _Col(this.print, this.x, this.width);

  final PrintColumn print;
  final double x;
  final double width;
}
