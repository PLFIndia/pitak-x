/// Turning picture bytes into a picture of a PDF document (infrastructure
/// layer, AGENTS.md §3.1; ADR 0033).
///
/// Two callers with two different needs share this file:
///  - the logo and the footer icon are DECORATION: a file that cannot be
///    decoded is skipped and the export goes on ([tryDecodePdfImage]);
///  - a text tile is CONTENT: a title that cannot be drawn must end the
///    export (`PdfTextTiles`, which calls [decodePdfImage] itself).
///
/// The decoder is a parameter ([PdfImageDecoder]) so that a test can make
/// it fail in ways real bytes cannot be made to fail on demand, running out
/// of memory above all.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';

/// Decodes [bytes] (PNG or JPEG) into a picture of [doc], or throws.
typedef PdfImageDecoder = PdfImage Function(PdfDocument doc, Uint8List bytes);

/// The decoder the app uses: `PdfImage.file` of the `pdf` package. It throws
/// when the bytes are no picture it knows (a plain `String`, from the
/// package), and whatever `package:image` throws on damaged data.
PdfImage decodePdfImage(PdfDocument doc, Uint8List bytes) =>
    PdfImage.file(doc, bytes: bytes);

/// Decodes a DECORATIVE picture (the library's logo, the footer icon), or
/// answers `null` when there is none or it cannot be decoded (empty bytes
/// included: the decoder refuses them): a bad logo must never stop an
/// export.
///
/// The one thing that is not skipped is running out of memory. Going on
/// after that would only fail again a moment later, somewhere less clear;
/// passed on, it reaches the export's own handling and the user is told.
PdfImage? tryDecodePdfImage(
  PdfDocument doc,
  Uint8List? bytes, {
  PdfImageDecoder decode = decodePdfImage,
}) {
  if (bytes == null) return null;
  try {
    return decode(doc, bytes);
  } on Object catch (error) {
    if (error is OutOfMemoryError) rethrow;
    // A bad logo/icon must never abort the export; just skip it.
    return null;
  }
}
