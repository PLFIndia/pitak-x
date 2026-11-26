/// Text tiles of the PDF book list (infrastructure layer, AGENTS.md §3.1;
/// ADR 0033).
///
/// A "tile" is one piece of text that the platform's text engine has drawn
/// as a picture and that is already embedded in the PDF document. The
/// renderer (`pdf_library_renderer.dart`) asks this file for the tile of
/// every text it draws. The answer is one of three:
///
///  - `null`: the text needs NO picture. It is plain (`isPlainPdfText`: Latin
///    letters, digits, common signs) and the document's font has a glyph for
///    every character of it, so the renderer writes it as real text.
///  - a [PdfTextTile]: the text needs shaping (Devanagari, Tamil, Arabic …)
///    or has a character the font lacks, and the engine has drawn it.
///  - a thrown [PdfTextPictureMissing]: the text needs a picture and none
///    could be made. The export ENDS. A text is never left out silently and
///    never written with a font that would draw it wrongly: a catalogue
///    with a missing or garbled title is worse than no catalogue.
///
/// WHY NOT A PICTURE FOR EVERYTHING (as it was until 2026-11): a picture is
/// two objects of the PDF document, and a document can hold only some
/// thousand of them while it is built. A catalogue of a few thousand books
/// did not fit. Most catalogues are mostly Latin text and digits (row
/// numbers, ISBNs, years), which need no picture at all.
///
/// COUNTING WITHOUT MAKING: before a PDF is made the app counts what it will
/// hold (`pdf_object_count.dart`). The count asks this file the very same
/// questions in the very same order, with `makePictures: false`: every
/// decision is taken as in a drawing pass (which text is a picture, which
/// key the cache holds, which key it forgets), but no picture is made. That
/// one code path is why the count cannot drift away from the drawing.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_plain_text.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_image_decode.dart';

/// A shaped text run already embedded in the document: the image XObject
/// handle plus the metrics needed to place it. The PNG bytes are NOT kept —
/// once the XObject exists they have no further use.
class PdfTextTile {
  /// Creates a tile for an embedded [image] with its placement metrics.
  const PdfTextTile(this.image, this.widthPt, this.heightPt, this.baselinePt);

  /// The picture, as an object of the PDF document.
  final PdfImage image;

  /// Width on the page, in PDF points.
  final double widthPt;

  /// Height on the page, in PDF points.
  final double heightPt;

  /// Distance from the tile's top edge down to the text baseline, in points.
  final double baselinePt;
}

/// Thrown when a text needs a picture and none could be made: there is no
/// rasterizer, the rasterizer answered nothing, or its bytes are no picture.
/// It ends the export (see the library doc).
///
/// It carries NO text on purpose. A title or a name is the user's data, and
/// an error's text can end up in a log.
class PdfTextPictureMissing implements Exception {
  /// Creates the signal.
  const PdfTextPictureMissing();

  @override
  String toString() => 'PdfTextPictureMissing';
}

/// Decides for each text whether it needs a picture, and makes the pictures
/// through the rasterizer.
///
/// [pinned] is for the page chrome (a handful of strings the caller holds for
/// the whole render). [row] is for body text and goes through a bounded
/// least-recently-used cache of `maxEntries` keys: a hit moves the key to the
/// back, an insert past the bound evicts the front (oldest) key. Only texts
/// that ARE pictures take a key: a plain text costs nothing to "make", and
/// keeping it would push a real picture out of the cache.
///
/// Dart's default `Map` is insertion-ordered (a `LinkedHashMap`), which is
/// all an LRU needs — no extra package (AGENTS.md §9). The same remove-and-
/// reinsert idiom is what `package:quiver`'s `LruMap` does internally.
class PdfTextTiles {
  /// Creates a tile source for [_doc].
  ///
  /// [regular] and [bold] are the document's fonts for the two weights; a
  /// text they can write gets no picture. [_rasterizer] makes the pictures;
  /// without one, a text that needs a picture ends the run. [maxEntries]
  /// bounds the row cache (at least one key is kept). [decode] turns the
  /// rasterizer's bytes into a picture of the document (a parameter for
  /// tests; see `pdf_image_decode.dart`).
  ///
  /// With [makePictures] false this is a COUNTING pass (see the library
  /// doc): the rasterizer is never asked, nothing is added to the document,
  /// and [row] and [pinned] always answer `null`. Only [picturesMade] and
  /// [cachedCount] are read then.
  PdfTextTiles(
    this._doc,
    this._rasterizer,
    int maxEntries, {
    required PdfFontResolver regular,
    required PdfFontResolver bold,
    PdfImageDecoder decode = decodePdfImage,
    bool makePictures = true,
  }) : _maxEntries = maxEntries < 1 ? 1 : maxEntries,
       _regular = regular,
       _bold = bold,
       _decode = decode,
       _makePictures = makePictures;

  final PdfDocument _doc;
  final PdfTextRasterizer? _rasterizer;
  final int _maxEntries;
  final PdfFontResolver _regular;
  final PdfFontResolver _bold;
  final PdfImageDecoder _decode;
  final bool _makePictures;

  /// The cache: a key for each row text that is a picture, oldest first. The
  /// value is the picture, or `null` in a counting pass, which holds the
  /// keys alone.
  final Map<String, PdfTextTile?> _lru = {};
  int _picturesMade = 0;

  /// Row tiles currently cached (reported through `PdfRenderProgress`).
  int get cachedCount => _lru.length;

  /// How many pictures were made so far, the page chrome and the rows
  /// together; in a counting pass, how many WOULD have been made. Each is
  /// two objects of the document (`PdfObjectCount.objectsPerPicture`).
  int get picturesMade => _picturesMade;

  /// Whether [text] has to be drawn as a picture: it is not plain, or the
  /// font of its weight lacks one of its characters. An empty text needs
  /// nothing.
  bool needsPicture(String text, {required bool bold}) {
    if (text.isEmpty) return false;
    final font = bold ? _bold : _regular;
    return !(isPlainPdfText(text) && font.canDraw(text));
  }

  /// A chrome tile, not cached here — the caller keeps the reference.
  /// `null` when [text] is written as real text (and always in a counting
  /// pass, which counts the picture instead of making it).
  Future<PdfTextTile?> pinned(
    String text,
    double size,
    PdfColor color, {
    required bool bold,
  }) async {
    if (!needsPicture(text, bold: bold)) return null;
    return _picture(text, size, color, bold: bold);
  }

  /// A body tile through the bounded cache (regular weight). `null` when
  /// [text] is written as real text (and always in a counting pass).
  Future<PdfTextTile?> row(String text, double size, PdfColor color) async {
    if (!needsPicture(text, bold: false)) return null;
    final key = 'R|$size|${color.toInt()}|$text';
    // Asked by key, not by value: in a counting pass the value is null.
    if (_lru.containsKey(key)) {
      // Hit: put it back at the end (most recently used).
      final hit = _lru.remove(key);
      _lru[key] = hit;
      return hit;
    }
    // A text whose picture fails throws here and leaves no key behind.
    final made = await _picture(text, size, color, bold: false);
    _lru[key] = made;
    if (_lru.length > _maxEntries) _lru.remove(_lru.keys.first);
    return made;
  }

  /// Makes the picture of [text], or throws [PdfTextPictureMissing]. In a
  /// counting pass it only notes that a picture would be made here, and
  /// answers `null`.
  Future<PdfTextTile?> _picture(
    String text,
    double size,
    PdfColor color, {
    required bool bold,
  }) async {
    if (!_makePictures) {
      _picturesMade += 1;
      return null;
    }
    final rasterizer = _rasterizer;
    if (rasterizer == null) throw const PdfTextPictureMissing();
    final raster = await rasterizer.raster(
      text,
      fontSize: size,
      bold: bold,
      colorArgb: color.toInt() | 0xFF000000,
    );
    if (raster == null) throw const PdfTextPictureMissing();
    final tile = PdfTextTile(
      _embed(raster.pngBytes),
      raster.widthPt,
      raster.heightPt,
      raster.baselinePt,
    );
    // Counted only once it exists: a picture that failed threw above.
    _picturesMade += 1;
    return tile;
  }

  /// Makes [pngBytes] a picture of the document, or throws
  /// [PdfTextPictureMissing] when they are no picture (no bytes at all are
  /// no picture either: the decoder refuses them).
  PdfImage _embed(Uint8List pngBytes) {
    try {
      return _decode(_doc, pngBytes);
    } on Object catch (error) {
      // Out of memory is not a bad picture: it is passed on as it is, and
      // the export's own handling tells the user.
      if (error is OutOfMemoryError) rethrow;
      // The `pdf` package throws a plain String for bytes it cannot decode,
      // and `package:image` its own errors for damaged data. Whatever it
      // was, this text has no picture: one typed signal, without the text.
      throw const PdfTextPictureMissing();
    }
  }
}
