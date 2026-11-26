/// The PDF of a book list: counted first, drawn only when it fits
/// (application layer, AGENTS.md §3; ADR 0033).
///
/// WHY COUNT FIRST (beginner note): a PDF can hold only some thousand pages
/// and pictures of text while it is built, on any phone. Without the count a
/// long list ran for most of a minute and then ended with "Export failed.".
/// With it, the app knows before any work is done, and can say how many of
/// the list's books fit.
///
/// The export use case (`export_library_use_case.dart`) calls this for the
/// PDF format. It is a file of its own so that the two calls of the renderer
/// stand side by side with the same arguments, and so that the use case's
/// file stays within the size the repository allows.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Asks [renderer] what the PDF of [books] would hold, and has it drawn only
/// when it fits into one PDF.
///
/// Returns the PDF's bytes, or a [PdfTooLargeFailure] with how many books
/// the list has and how many would fit; then nothing was drawn, and
/// [textRasterizer] was not asked for a single picture. A catalogue with its
/// end missing is never made (it would look complete).
///
/// The count and the drawing are handed the very same things: the count is
/// only true for the list, the columns, the fonts and the logo it was given.
///
/// [cancelToken] stops either of the two at its next row; a cancelled run
/// throws [PdfRenderCancelled], which the caller that owns the token catches.
/// The other arguments are those of [LibraryPdfRenderer.render].
Future<Either<Failure, Uint8List>> exportLibraryPdf(
  LibraryPdfRenderer renderer, {
  required String libraryName,
  required String? subtitle,
  required List<CatalogueItem> books,
  required List<PrintColumn> columns,
  required String footerAttribution,
  required PdfFontBundle regularFonts,
  required PdfFontBundle boldFonts,
  Uint8List? logoBytes,
  Uint8List? footerIconBytes,
  PdfTextRasterizer? textRasterizer,
  PdfRenderProgressListener? onProgress,
  RenderCancelToken? cancelToken,
}) async {
  final size = await renderer.measure(
    libraryName: libraryName,
    subtitle: subtitle,
    books: books,
    columns: columns,
    footerAttribution: footerAttribution,
    regularFonts: regularFonts,
    boldFonts: boldFonts,
    logoBytes: logoBytes,
    footerIconBytes: footerIconBytes,
    cancelToken: cancelToken,
  );
  if (!size.fits) {
    return left(
      PdfTooLargeFailure(books: size.rowsTotal, booksThatFit: size.rowsThatFit),
    );
  }
  final bytes = await renderer.render(
    libraryName: libraryName,
    subtitle: subtitle,
    books: books,
    columns: columns,
    footerAttribution: footerAttribution,
    regularFonts: regularFonts,
    boldFonts: boldFonts,
    logoBytes: logoBytes,
    footerIconBytes: footerIconBytes,
    textRasterizer: textRasterizer,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
  return right(bytes);
}
