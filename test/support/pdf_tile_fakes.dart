/// Stand-ins for the tests of the PDF renderer and of its text tiles.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';

/// A REAL picture, 1 x 1 with transparency, encoded by `package:image`, so
/// that `PdfImage.file` decodes it and a stand-in tile takes the real embed
/// path (decode, then two objects of the PDF document: the pixels and their
/// transparency).
///
/// It is MADE here and not written out as bytes on purpose: until 2026-11
/// the renderer's tests carried a hand-typed 1 x 1 PNG that no decoder took,
/// and nobody noticed, because the renderer then fell back to plain text.
/// `pdf_text_tiles_test.dart` checks that this one decodes.
final Uint8List tinyPngPicture = Uint8List.fromList(
  im.encodePng(im.Image(width: 1, height: 1, numChannels: 4)),
);

/// Bytes that are no picture at all.
final Uint8List notAPicture = Uint8List.fromList([1, 2, 3, 4]);

/// How many pictures a finished PDF holds, read from its bytes: every
/// picture object says `/Subtype/Image` in plain text. One embedded tile
/// with transparency counts as TWO (see [tinyPngPicture]).
int countPdfPictureObjects(List<int> pdfBytes) => RegExp(
  r'/Subtype\s*/Image',
).allMatches(String.fromCharCodes(pdfBytes)).length;

/// How many STREAM objects a finished PDF holds, read from its bytes: every
/// one ends with the word `endstream`. These are what the count before a run
/// counts (ADR 0033): one for each page, two for each picture, two for each
/// TrueType font, and one that the file itself adds (its table of contents).
int countPdfStreamObjects(List<int> pdfBytes) =>
    'endstream'.allMatches(String.fromCharCodes(pdfBytes)).length;

/// Counts every text the renderer asks a picture for and remembers the
/// order, so a test can tell WHICH texts became pictures and WHEN.
///
/// By default every text gets [tinyPngPicture]; [answer] replaces that for
/// one test (a `null` answer, bytes that are no picture, a thrown error).
/// With [yieldPerCall] it gives the event loop a turn per call, as the real
/// `dart:ui` rasterizer does.
class CountingPdfRasterizer implements PdfTextRasterizer {
  /// Creates the stand-in.
  CountingPdfRasterizer({this.yieldPerCall = false, this.answer});

  /// Whether each call waits one turn of the event loop.
  final bool yieldPerCall;

  /// What to answer for a text instead of the default picture.
  final RasterizedText? Function(String text)? answer;

  /// Every text asked for, in order.
  final List<String> runs = [];

  /// The default answer: a tile of [bytes] sized by the text's length.
  static RasterizedText tileOf(String text, {Uint8List? bytes}) =>
      RasterizedText(
        pngBytes: bytes ?? tinyPngPicture,
        widthPt: text.length * 6.0,
        heightPt: 14,
        baselinePt: 11,
      );

  @override
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  }) async {
    runs.add(text);
    if (yieldPerCall) await Future<void>.delayed(Duration.zero);
    final custom = answer;
    return custom != null ? custom(text) : tileOf(text);
  }
}
