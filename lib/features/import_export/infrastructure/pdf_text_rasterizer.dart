/// Shapes text with Flutter's engine (HarfBuzz) and rasterizes it to a PNG tile
/// for embedding in the PDF (infrastructure layer).
///
/// WHY THIS EXISTS: the `pdf` package's `drawString` maps codepoints to glyphs
/// 1:1 with NO complex-script shaping (it ships shaping for Arabic only). For
/// Indic scripts that breaks conjuncts / half-letters and matra reordering — e.g.
/// "बच्चे" renders as full letters with a visible halant instead of the ्च
/// half-form. The Kotlin app avoids this by drawing on an Android `Canvas`,
/// which shapes via the OS. The cross-platform equivalent is to let Flutter's
/// own text engine shape + lay out each run, capture it as an image, and embed
/// that image in the PDF. The tradeoff (chosen with the user): PDF text becomes
/// raster, not selectable — acceptable for a printable catalogue.
///
/// This is the side-effecting edge (uses `dart:ui` + a live engine), kept away
/// the pure `PdfLibraryRenderer` layout maths and injected into it, so the
/// renderer stays unit-testable and this stays the one place that needs a
/// Flutter engine (a widget test, not a pure test).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

/// A shaped, rasterized text run ready to embed.
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

/// `dart:ui`-backed rasterizer. Registers the bundled Noto TTFs as runtime font
/// families (a fallback group, so the engine picks the right script per glyph)
/// and shapes each run with a [ui.ParagraphBuilder].
class UiPdfTextRasterizer implements PdfTextRasterizer {
  /// Creates a rasterizer over the ordered [regularAssets] / [boldAssets] font
  /// asset paths (base/Latin first, then Indic fallbacks). [scale] is the
  /// supersampling factor for crisp print output.
  UiPdfTextRasterizer({
    required List<String> regularAssets,
    required List<String> boldAssets,
    this.scale = 3.0,
  }) : _regularAssets = regularAssets,
       _boldAssets = boldAssets;

  /// Family name the regular Noto fonts are registered under.
  static const String regularFamily = 'PitakPdfRegular';

  /// Family name the bold Noto fonts are registered under.
  static const String boldFamily = 'PitakPdfBold';

  final List<String> _regularAssets;
  final List<String> _boldAssets;

  /// Supersampling factor (device px per point) for the rasterized tiles.
  final double scale;

  bool _fontsLoaded = false;

  /// Registers all bundled TTFs once. Each family is loaded with MULTIPLE fonts
  /// so the engine treats them as a fallback group (Latin base + Indic faces):
  /// a Devanagari run falls back to the Devanagari face automatically.
  Future<void> _ensureFonts() async {
    if (_fontsLoaded) return;
    await _loadFamily(regularFamily, _regularAssets);
    await _loadFamily(boldFamily, _boldAssets);
    _fontsLoaded = true;
  }

  static Future<void> _loadFamily(String family, List<String> assets) async {
    if (assets.isEmpty) return;
    final fontLoader = FontLoader(family);
    for (final asset in assets) {
      fontLoader.addFont(rootBundle.load(asset));
    }
    await fontLoader.load();
  }

  @override
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  }) async {
    if (text.isEmpty) return null;
    await _ensureFonts();

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: bold ? boldFamily : regularFamily,
              fontSize: fontSize,
              maxLines: 1,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: ui.Color(colorArgb),
              fontSize: fontSize,
              fontFamily: bold ? boldFamily : regularFamily,
            ),
          )
          ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final widthPt = paragraph.maxIntrinsicWidth;
    final heightPt = paragraph.height;
    if (widthPt <= 0 || heightPt <= 0) return null;
    final baselinePt = paragraph.alphabeticBaseline;

    final pxW = (widthPt * scale).ceil();
    final pxH = (heightPt * scale).ceil();
    if (pxW <= 0 || pxH <= 0) return null;

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(scale)
      ..drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(pxW, pxH);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return RasterizedText(
        pngBytes: data.buffer.asUint8List(),
        widthPt: widthPt,
        heightPt: heightPt,
        baselinePt: baselinePt,
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
