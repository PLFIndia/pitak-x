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
///
/// MEMORY / RESPONSIVENESS (N10-e, `astra-review.md` N10): in shaped-image
/// mode every text run is rasterized by the platform text engine, which only
/// works on the UI isolate. The renderer therefore
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
/// What this does NOT bound: the `pdf` package keeps every embedded image
/// XObject on `PdfDocument.objects` until `save()` (that is how pages
/// reference them), so the decoded bitmaps of a shaped-text PDF still scale
/// with pages × tiles-per-page. `save()` itself already runs in a worker
/// isolate (`pdf` 3.12 `pdfCompute`).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Renders a book list to a paginated PDF and returns the encoded bytes.
class PdfLibraryRenderer implements LibraryPdfRenderer {
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

  /// Default bound on ROW text tiles held at once (N10-e, decision D5-b).
  /// The widest layout (14 landscape columns) needs roughly 400 tiles per
  /// page, so 512 keeps one page's working set plus repeated short cells
  /// without thrashing; each entry is a decoded-image handle plus three
  /// doubles, so the cache itself stays tiny.
  static const int defaultMaxCachedTiles = 512;

  /// Rows between explicit event-loop yields (see the library doc).
  static const int _yieldEveryRows = 20;

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
  ///
  /// [onProgress], [cancelToken] and [maxCachedTiles]: see the library doc
  /// and [LibraryPdfRenderer.render].
  @override
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
    PdfRenderProgressListener? onProgress,
    RenderCancelToken? cancelToken,
    int maxCachedTiles = defaultMaxCachedTiles,
  }) async {
    // A token cancelled before we start renders nothing at all.
    cancelToken?.throwIfCancelled();

    final doc = PdfDocument();

    // When a rasterizer is supplied, text is shaped by Flutter's engine
    // (HarfBuzz) and embedded as images so complex scripts (Devanagari joins
    // / half-letters, matra reordering) render correctly — `drawString` cannot
    // shape them. Tiles are produced per ROW (below) through a bounded cache;
    // a null tile means "fall back to drawString". When no rasterizer is
    // supplied (Latin-only callers, pure tests) every tile is null.
    final tiles = _TileSource(doc, textRasterizer, maxCachedTiles);

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

    // Draws one run. [tile] is the pre-rasterized shaped image for exactly
    // this string/size/weight (or null → `drawString`). Passing the tile in
    // explicitly (rather than looking it up) means a row is always drawn
    // with the tiles it just produced, whatever the cache did meanwhile.
    void drawText(
      PdfGraphics g,
      String s,
      double x,
      double y,
      PdfFontResolver font,
      double size,
      PdfColor color,
      _Tile? tile,
    ) {
      if (s.isEmpty) return;
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
    final serialHeaderTile = await tiles.pinned(
      serialHeader,
      headerText,
      _black,
      bold: true,
    );
    final colHeaderTexts = [
      for (final col in cols) _ellipsize(col.print.header, maxChars(col.width)),
    ];
    final colHeaderTiles = <_Tile?>[
      for (final text in colHeaderTexts)
        await tiles.pinned(text, headerText, _black, bold: true),
    ];
    final footerTile = await tiles.pinned(
      footerAttribution,
      footerText,
      _footerGrey,
      bold: false,
    );

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
        footerTile,
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
      drawText(g, libraryName, nameX, top, bold, titleText, _black, titleTile);
      const logoOrText = headerLogo > 22 ? headerLogo : 22.0;
      return margin + logoOrText + 16;
    }

    double drawColumnHeaders(PdfGraphics g, double startY) {
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
        ..setStrokeColor(_black)
        ..setLineWidth(1)
        ..drawLine(contentLeft, ty(ruleY), contentRight, ty(ruleY))
        ..strokePath();
      return startY + lineHeight + 2;
    }

    // --- pagination loop --------------------------------------------------

    // The pdf package numbers pages implicitly by insertion order, so we just
    // append a new PdfPage when a row overflows the printable area.
    var pages = 1;
    var page = PdfPage(doc, pageFormat: PdfPageFormat(pageW, pageH));
    var g = page.getGraphics();
    var y = drawHeader(g);
    y = drawColumnHeaders(g, y);
    drawFooter(g);

    void report(int rowsDone) => onProgress?.call(
      PdfRenderProgress(
        rowsDone: rowsDone,
        rowsTotal: books.length,
        pagesDone: pages,
        cachedTiles: tiles.cachedCount,
      ),
    );
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

      // Rasterize THIS row's runs now (N10-e): the serial and every wrapped
      // cell line, in draw order. Nothing beyond this row is touched.
      final serialText = '$serial';
      final serialTile = await tiles.row(serialText, bodyText, _black);
      final lineTiles = <List<_Tile?>>[
        for (final lines in cellLines)
          <_Tile?>[
            for (final line in lines) await tiles.row(line, bodyText, _black),
          ],
      ];

      if (y + rowHeight > rowBottomLimit) {
        pages += 1;
        page = PdfPage(doc, pageFormat: PdfPageFormat(pageW, pageH));
        g = page.getGraphics();
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

/// A shaped text run already embedded in the document: the image XObject
/// handle plus the metrics needed to place it. The PNG bytes are NOT kept —
/// once the XObject exists they have no further use.
class _Tile {
  const _Tile(this.image, this.widthPt, this.heightPt, this.baselinePt);

  final PdfImage image;
  final double widthPt;
  final double heightPt;
  final double baselinePt;
}

/// Produces [_Tile]s through the rasterizer and embeds them in the document.
///
/// [pinned] is for the page chrome (a handful of strings the caller holds for
/// the whole render). [row] is for body text and goes through a bounded
/// least-recently-used cache of `maxEntries` keys: a hit moves the key to the
/// back, an insert past the bound evicts the front (oldest) key. A `null`
/// value ("this run has no usable tile, use drawString") is cached too, so
/// the rasterizer is asked once per distinct run while the key is resident.
///
/// Dart's default `Map` is insertion-ordered (a `LinkedHashMap`), which is
/// all an LRU needs — no extra package (AGENTS.md §9). The same remove-and-
/// reinsert idiom is what `package:quiver`'s `LruMap` does internally.
class _TileSource {
  _TileSource(this._doc, this._rasterizer, int maxEntries)
    : _maxEntries = maxEntries < 1 ? 1 : maxEntries;

  final PdfDocument _doc;
  final PdfTextRasterizer? _rasterizer;
  final int _maxEntries;
  final Map<String, _Tile?> _lru = {};

  /// Row tiles currently cached (reported through [PdfRenderProgress]).
  int get cachedCount => _lru.length;

  /// A chrome tile, not cached here — the caller keeps the reference.
  Future<_Tile?> pinned(
    String text,
    double size,
    PdfColor color, {
    required bool bold,
  }) => _make(text, size, color, bold: bold);

  /// A body tile through the bounded cache (regular weight).
  Future<_Tile?> row(String text, double size, PdfColor color) async {
    if (_rasterizer == null || text.isEmpty) return null;
    final key = 'R|$size|${color.toInt()}|$text';
    if (_lru.containsKey(key)) {
      // Hit: move to the back (most recently used).
      final hit = _lru.remove(key);
      _lru[key] = hit;
      return hit;
    }
    final made = await _make(text, size, color, bold: false);
    _lru[key] = made;
    if (_lru.length > _maxEntries) _lru.remove(_lru.keys.first);
    return made;
  }

  Future<_Tile?> _make(
    String text,
    double size,
    PdfColor color, {
    required bool bold,
  }) async {
    final rasterizer = _rasterizer;
    if (rasterizer == null || text.isEmpty) return null;
    final raster = await rasterizer.raster(
      text,
      fontSize: size,
      bold: bold,
      colorArgb: color.toInt() | 0xFF000000,
    );
    if (raster == null) return null;
    final image = PdfLibraryRenderer._tryDecode(_doc, raster.pngBytes);
    if (image == null) return null;
    return _Tile(image, raster.widthPt, raster.heightPt, raster.baselinePt);
  }
}
