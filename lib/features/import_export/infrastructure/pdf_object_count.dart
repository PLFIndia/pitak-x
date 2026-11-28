/// Counting what a PDF will hold BEFORE it is made (infrastructure layer,
/// AGENTS.md §3.1; ADR 0033).
///
/// WHY A COUNT AND NOT A SIZE (beginner note): while the `pdf` package builds
/// a document, every "stream object" of it (a page's content, a picture, a
/// picture's transparency, an embedded font) keeps a buffer that starts at
/// 64 KiB. On Android the Dart VM gives every piece of memory of that size a
/// place of its own, 512 KiB wide, in a region that has 8,192 such places
/// and no more, whatever the phone. So a document can have only some
/// thousand stream objects, however little each one holds, and a strong
/// phone can make no longer catalogue than a weak one. What has to be
/// counted is therefore OBJECTS, not bytes.
///
/// What costs objects, and how many (each number is held to the finished
/// file's own count by `pdf_library_measure_test.dart`, so an update of the
/// package that changes one of them fails a test):
///  - a page: one (its content);
///  - a picture of a text: two (the pixels, and their transparency);
///  - a TrueType font: two (the font file, and its character map); the
///    built-in font: none;
///  - the logo and the footer icon: two each as PNG, one as JPEG;
///  - the file itself: one (its table of contents is written as a stream).
library;

import 'package:pdf/pdf.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';

/// How many stream objects ONE PDF of the app may have.
///
/// WHY 7,000 (decision D214, 2026-11-25): the region has 8,192 places (see
/// the library doc) and everything else the app keeps in memory lives in it
/// too, so a document cannot have them all. Where a document really stops
/// was looked for on devices before the number was set:
///  - a debug build in an emulator made a PDF of 7,661 objects and saved
///    it, and ran out of places somewhere above 7,758;
///  - a release build on a phone ran out at about 8,090. That was the code
///    of before this change (2026-11-24); with today's code a phone made a
///    PDF of 6,048 objects, and was not run to where it stops.
/// 7,000 leaves about 660 places under the first and about 1,090 under the
/// second. A run that runs out all the same ends with a sentence of its
/// own (`ExportOutcome.outOfMemory`).
///
/// What a higher number would cost besides: every object also takes memory
/// of the device until the file is written. On a phone, in a release
/// build, a PDF of 6,048 objects took about 85 KiB an object at its most
/// (2026-11-25), which is about 580 MB at this budget; a debug build in an
/// emulator took about 63 KiB an object.
///
/// Changing it is a decision, not a tidy-up: `pdf_object_count_test.dart`
/// holds the number a second time.
const int pdfStreamObjectBudget = 7000;

/// Stream objects a TrueType font adds to a document: the embedded font
/// file and its character map.
const int _objectsPerTrueTypeFont = 2;

/// Stream objects the finished FILE adds to those of the document: its
/// cross-reference table (the table of contents) is written as one.
const int _objectsOfTheFile = 1;

/// The stream objects [doc] has before any page or text picture is added:
/// those of its fonts, of the pictures decoded into it so far (the logo, the
/// footer icon), and the one the finished file adds.
///
/// It is read off the real document, after the real fonts and pictures went
/// into it, so nothing here is guessed from a file's name or first bytes.
int pdfFixedStreamObjects(PdfDocument doc) {
  var objects = _objectsOfTheFile;
  for (final object in doc.objects) {
    if (object is PdfTtfFont) objects += _objectsPerTrueTypeFont;
    // A picture with transparency is two `PdfImage` objects of the document
    // already, so each one found counts once.
    if (object is PdfImage) objects += 1;
  }
  return objects;
}

/// Keeps the count while a pass goes over the rows of a list, and remembers
/// how many rows were in when the budget ran out.
///
/// The pass tells it after every row how many pages and pictures the
/// document has by then ([rowsDone]); at the end [estimate] gives the answer
/// for the whole list.
class PdfObjectCount {
  /// Creates a count over [fixedObjects] (see [pdfFixedStreamObjects]) with
  /// a budget of [maxObjects].
  PdfObjectCount({required this.fixedObjects, required this.maxObjects});

  /// Stream objects of one picture of a text: its pixels, and their
  /// transparency.
  static const int objectsPerPicture = 2;

  /// What the document has before its first page.
  final int fixedObjects;

  /// The budget: how many stream objects the document may have.
  final int maxObjects;

  int _rowsThatFit = 0;

  /// The stream objects of a document with this many [pages] and text
  /// [pictures].
  int objectsFor({required int pages, required int pictures}) =>
      fixedObjects + pages + objectsPerPicture * pictures;

  /// Notes that [rows] rows are laid out, and that the document has [pages]
  /// pages and [pictures] text pictures by then. Called in the order of the
  /// rows, with 0 before the first.
  ///
  /// A document never loses a page or a picture, so the count only grows:
  /// the last call that was still within the budget names the rows that fit.
  void rowsDone(int rows, {required int pages, required int pictures}) {
    if (objectsFor(pages: pages, pictures: pictures) <= maxObjects) {
      _rowsThatFit = rows;
    }
  }

  /// The answer for the whole list of [rowsTotal] rows, with the [pages] and
  /// [pictures] the document has at the END of the pass.
  PdfSizeEstimate estimate({
    required int rowsTotal,
    required int pages,
    required int pictures,
  }) => PdfSizeEstimate(
    objectsNeeded: objectsFor(pages: pages, pictures: pictures),
    objectsAllowed: maxObjects,
    rowsTotal: rowsTotal,
    rowsThatFit: _rowsThatFit,
  );
}
