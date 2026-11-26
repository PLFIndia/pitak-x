/// Domain port for the paginated PDF library-list renderer (review finding
/// N14: PDF rendering used to live inside the domain layer).
///
/// The concrete renderer lives in `infrastructure/` — it depends on the
/// `pdf` package, which is an output-format engine and therefore not domain
/// code (AGENTS.md §3.1). The export use case depends on this narrow port
/// and receives the implementation via DI.
library;

import 'dart:typed_data';

import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Raw TTF bytes for one weight (regular or bold), ordered by preference.
///
/// The FIRST entry is the primary/base font (Latin); the rest are script
/// fallbacks tried in order. Pure data — the font "resolution" that needs the
/// pdf package lives in infrastructure with the renderer.
typedef PdfFontBundle = List<ByteData>;

/// The fonts a PDF's REAL text is written with, one bundle for each weight.
/// Pure data, as [PdfFontBundle] is; the app loads them from its assets at
/// the edge and hands them inward.
typedef PdfTextFonts = ({PdfFontBundle regular, PdfFontBundle bold});

/// What a PDF of a book list would hold, counted BEFORE it is made (ADR 0033).
///
/// Why this exists (beginner note): while a PDF is built, each of its pages
/// and each picture of a text takes a fixed piece of the app's memory, and
/// there are only some thousand such pieces, on a strong phone as on a weak
/// one. A list that needs more cannot be made at all. Counting first lets the
/// app say so at once, in a sentence with numbers, instead of failing after
/// a long wait.
///
/// Pure data: numbers only, so it can cross every layer.
class PdfSizeEstimate {
  /// Creates an estimate.
  const PdfSizeEstimate({
    required this.objectsNeeded,
    required this.objectsAllowed,
    required this.rowsTotal,
    required this.rowsThatFit,
  });

  /// How many objects the PDF of the WHOLE list would have (pages, pictures
  /// of text, fonts, the logo).
  final int objectsNeeded;

  /// How many objects one PDF may have: the renderer's budget.
  final int objectsAllowed;

  /// The rows (books) of the list.
  final int rowsTotal;

  /// How many rows, counted from the first, a PDF within the budget can
  /// hold. Equal to [rowsTotal] when the whole list fits.
  final int rowsThatFit;

  /// Whether the whole list fits into one PDF.
  bool get fits => objectsNeeded <= objectsAllowed;
}

/// Renders a book list to a paginated A4 PDF and returns the encoded bytes;
/// and says beforehand whether the list fits into one PDF. An interface (the
/// repo's port style — see the `Importer` port) so the export use case
/// depends on the abstraction, not the infrastructure renderer.
abstract interface class LibraryPdfRenderer {
  /// Counts what [render] would make of the same arguments, WITHOUT making
  /// it: no picture is drawn and no page is written, so it is quick and
  /// needs little memory, however long the list is (ADR 0033).
  ///
  /// The caller asks this first and calls [render] only when the answer
  /// [PdfSizeEstimate.fits]. Hand both the same arguments: the count walks
  /// the rows exactly as [render] does, and is only as true as its inputs.
  ///
  /// [cancelToken] is checked at every row boundary, as in [render]; a
  /// cancelled count throws [PdfRenderCancelled].
  Future<PdfSizeEstimate> measure({
    required String libraryName,
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    String? subtitle,
    PdfFontBundle regularFonts,
    PdfFontBundle boldFonts,
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    RenderCancelToken? cancelToken,
    int maxCachedTiles,
  });

  /// Renders [books] under [libraryName] with the chosen [columns].
  ///
  /// [subtitle] (optional) is one line drawn under the library name on
  /// every page — what a filtered list IS ("Donated by Ram Sharma"), so a
  /// printed subset can never be mistaken for the whole catalogue. Null or
  /// blank draws nothing and the layout is unchanged.
  ///
  /// How a text gets onto the page (ADR 0033): a text that needs no shaping
  /// (`isPlainPdfText`) and that the font of its weight can write is REAL
  /// text, written with [regularFonts]/[boldFonts] (TTF byte bundles; when
  /// empty, a built-in font that knows Latin-1 only). Every other text is a
  /// picture made by [textRasterizer], which shapes it with the platform's
  /// engine. A text that needs a picture and gets none (no rasterizer, or
  /// one that fails) ENDS the render with an error: nothing is left out or
  /// written unshaped. [logoBytes]/[footerIconBytes] are optional images.
  ///
  /// N10-e: [onProgress] is called once before the first row, once after
  /// every row and once at the end; [cancelToken] is checked at every row
  /// boundary and a cancelled render throws [PdfRenderCancelled] (no bytes
  /// are produced). The renderer holds at most [maxCachedTiles] rasterized
  /// text tiles at any time.
  Future<Uint8List> render({
    required String libraryName,
    required List<CatalogueItem> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    String? subtitle,
    PdfFontBundle regularFonts,
    PdfFontBundle boldFonts,
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    PdfTextRasterizer? textRasterizer,
    PdfRenderProgressListener? onProgress,
    RenderCancelToken? cancelToken,
    int maxCachedTiles,
  });
}
