/// Where the columns of the PDF book list stand on the page (infrastructure
/// layer, AGENTS.md §3.1).
///
/// Plain arithmetic, with no drawing in it: the pass over the rows
/// (`pdf_library_pass.dart`) asks it once per document for the columns'
/// places and once per cell for how many characters fit. It was part of the
/// renderer until 2026-11 and moved here, unchanged, to keep that file
/// within the size the repository allows.
library;

import 'package:pitaka/features/import_export/domain/pdf_column.dart';

/// A resolved column with its laid-out x-offset and width, in points.
class PdfColumnBox {
  /// Creates the box of [print] at [x], [width] wide.
  const PdfColumnBox(this.print, this.x, this.width);

  /// The column: its header and how a book's cell is read.
  final PrintColumn print;

  /// Left edge on the page.
  final double x;

  /// Width on the page.
  final double width;
}

/// Resolves each column's x-offset and width from its weight: [columns]
/// share [width] by weight, side by side from [left].
List<PdfColumnBox> layOutPdfColumns(
  List<PrintColumn> columns, {
  required double left,
  required double width,
}) {
  final totalWeight = columns
      .fold<double>(0, (a, c) => a + c.weight)
      .clamp(1, double.infinity);
  final boxes = <PdfColumnBox>[];
  var cx = left;
  for (final c in columns) {
    final w = width * (c.weight / totalWeight);
    boxes.add(PdfColumnBox(c, cx, w));
    cx += w;
  }
  return boxes;
}

/// Approx chars that fit a column [width] at the row text size. At 12pt, an
/// average Helvetica glyph is ~6.6pt wide.
int pdfCharsThatFit(double width) {
  final n = (width / 6.6).floor();
  return n < 3 ? 3 : n;
}

/// Hard truncate over-long header cells so columns don't overlap.
String ellipsizePdfHeader(String s, int max) {
  if (s.length <= max) return s;
  final keep = (max - 1) < 1 ? 1 : (max - 1);
  return '${s.substring(0, keep)}…';
}
