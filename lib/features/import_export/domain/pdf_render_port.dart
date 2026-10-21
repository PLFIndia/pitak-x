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

/// Renders a book list to a paginated A4 PDF and returns the encoded bytes.
/// Single-method, but kept as an interface (the repo's port style — see the
/// `Importer` port) so the export use case depends on the abstraction, not
/// the infrastructure renderer.
// ignore: one_member_abstracts
abstract interface class LibraryPdfRenderer {
  /// Renders [books] under [libraryName] with the chosen [columns].
  ///
  /// [subtitle] (optional) is one line drawn under the library name on
  /// every page — what a filtered list IS ("Donated by Ram Sharma"), so a
  /// printed subset can never be mistaken for the whole catalogue. Null or
  /// blank draws nothing and the layout is unchanged.
  ///
  /// [regularFonts]/[boldFonts] are ordered TTF byte bundles (base/Latin
  /// first, then script fallbacks); when empty, a Latin-only built-in font is
  /// used. [textRasterizer] (optional) shapes complex scripts via the
  /// platform engine; [logoBytes]/[footerIconBytes] are optional images.
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
