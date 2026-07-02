/// Shaped-text rasterization port for the PDF export (domain, AGENTS.md §3.3).
///
/// WHY: the `pdf` package's `drawString` has no complex-script shaping, so
/// Indic text renders wrong. The fix is to let a real text engine shape each
/// run and embed the result as an image. That engine (Flutter's `dart:ui`) is
/// a side effect, so THIS file declares only the pure contract — the
/// `dart:ui`-backed `UiPdfTextRasterizer` implements it in infrastructure and
/// is injected by the caller (dependencies point inward, §3.1).
library;

import 'dart:typed_data';

/// A shaped, rasterized text run ready to embed in the PDF.
class RasterizedText {
  /// Creates a rasterized run.
  const RasterizedText({
    required this.pngBytes,
    required this.widthPt,
    required this.heightPt,
    required this.baselinePt,
  });

  /// PNG-encoded image of the shaped run (supersampled for print sharpness).
  final Uint8List pngBytes;

  /// Logical width in PDF points (independent of supersampling).
  final double widthPt;

  /// Logical height in PDF points.
  final double heightPt;

  /// Distance from the tile's top edge down to the text baseline, in points.
  /// Used to align the embedded image to the renderer's baseline `y`.
  final double baselinePt;
}

/// Shapes one text run and returns it as a [RasterizedText], or null when the
/// run is empty / cannot be rendered (the caller then skips drawing it).
// ignore: one_member_abstracts
abstract interface class PdfTextRasterizer {
  /// Shapes [text] at [fontSize] points in the given weight/colour.
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  });
}
