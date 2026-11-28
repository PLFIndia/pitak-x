import 'dart:typed_data';

import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// A stand-in for the PDF renderer whose count and whose drawing END as a
/// test says (ADR 0033): the list does not fit, the count throws, the
/// drawing throws. Nothing is drawn; a run that is let through answers a
/// few bytes that look like the start of a PDF.
///
/// For the tests of what the export controller and the Export page make of
/// such an ending. The real count is tested with the real renderer
/// (`pdf_library_measure_test.dart`).
class EndingPdfRenderer implements LibraryPdfRenderer {
  /// Creates the stand-in. With no argument every list fits and is "drawn".
  EndingPdfRenderer({this.rowsThatFit, this.measureError, this.renderError});

  /// How many rows of the list fit into one PDF; `null` means all of them.
  final int? rowsThatFit;

  /// When given, the count throws it instead of answering.
  final Object? measureError;

  /// When given, the drawing throws it instead of answering.
  final Object? renderError;

  /// How often the count was asked.
  int measureCalls = 0;

  /// How often the drawing was asked.
  int renderCalls = 0;

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
    int maxCachedTiles = 512,
  }) async {
    measureCalls += 1;
    final error = measureError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    final fit = rowsThatFit ?? books.length;
    return PdfSizeEstimate(
      // One object over the budget when a row is left out; the numbers of
      // objects themselves are of no interest to these tests.
      objectsNeeded: fit < books.length ? 2 : 1,
      objectsAllowed: 1,
      rowsTotal: books.length,
      rowsThatFit: fit,
    );
  }

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
    int maxCachedTiles = 512,
  }) async {
    renderCalls += 1;
    final error = renderError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return Uint8List.fromList('%PDF-fake'.codeUnits);
  }
}
