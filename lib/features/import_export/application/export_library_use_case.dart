/// Export use case (application layer, AGENTS.md §3/§4).
///
/// Reads the library + wishlist and renders an export in the chosen
/// [ExportScope] and [ExportFormat]. JSON is canonical + round-trippable (read
/// by `PitakaJsonImporter`); CSV is a flat, spreadsheet-friendly library dump;
/// PDF is a paginated, printable book-list catalogue (Kotlin parity, always the
/// LIBRARY list regardless of scope). Bundle (covers zip) is deferred —
/// PLAN #24.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// What to include in an export.
enum ExportScope {
  /// Library books only.
  libraryOnly,

  /// Wishlist entries only.
  wishlistOnly,

  /// Both library and wishlist.
  both,
}

/// Output format for an export.
enum ExportFormat {
  /// Canonical Pitak JSON (round-trippable).
  json,

  /// Flat CSV (library rows; spreadsheet-friendly).
  csv,

  /// Paginated, printable PDF catalogue (library list).
  pdf,
}

/// A rendered export ready to write to a file.
class ExportResult {
  /// Creates a result over raw bytes.
  const ExportResult({
    required this.suggestedFileName,
    required this.bytes,
    required this.mimeType,
  });

  /// A sensible default file name (incl. extension).
  final String suggestedFileName;

  /// The serialised export payload (UTF-8 for text formats; binary for PDF).
  final Uint8List bytes;

  /// The MIME type to tag the saved file with.
  final String mimeType;
}

/// Reads the stores and renders an [ExportResult].
class ExportLibraryUseCase {
  /// Creates the use case over its collaborators.
  const ExportLibraryUseCase({
    required BookRepository bookRepo,
    required WishlistRepository wishlistRepo,
    PitakaJsonExporter jsonExporter = const PitakaJsonExporter(),
    PdfLibraryRenderer pdfRenderer = const PdfLibraryRenderer(),
  }) : _books = bookRepo,
       _wishlist = wishlistRepo,
       _json = jsonExporter,
       _pdf = pdfRenderer;

  final BookRepository _books;
  final WishlistRepository _wishlist;
  final PitakaJsonExporter _json;
  final PdfLibraryRenderer _pdf;

  /// Builds an export for [scope] in [format] at [now] (epoch millis stamp).
  ///
  /// PDF-only inputs are ignored by the other formats:
  ///  - [pdfColumns]: the user's column selection (defaults to the classic
  ///    set);
  ///  - [libraryName]: header title (defaults to "My Library");
  ///  - [footerIconBytes]: the Pitak app icon composited into the footer;
  ///  - [logoBytes]: the user's library logo drawn left of the header name
  ///    (decoded PNG/JPEG bytes); null → header shows the name only;
  ///  - [pdfRegularFonts]/[pdfBoldFonts]: ordered TTF bundles (Latin base first,
  ///    then Indic fallbacks) for mixed-script text. Empty = Latin-only.
  ///  - [textRasterizer]: when supplied, PDF text is shaped by Flutter's engine
  ///    and embedded as images so complex scripts (Devanagari half-letters /
  ///    matra reordering) render correctly; null keeps the Latin-only path.
  Future<Either<Failure, ExportResult>> call({
    required ExportScope scope,
    required ExportFormat format,
    int? now,
    List<PdfColumn>? pdfColumns,
    String libraryName = 'My Library',
    String libraryId = '',
    Uint8List? footerIconBytes,
    Uint8List? logoBytes,
    PdfFontBundle pdfRegularFonts = const [],
    PdfFontBundle pdfBoldFonts = const [],
    PdfTextRasterizer? textRasterizer,
  }) async {
    final stamp = now ?? DateTime.now().millisecondsSinceEpoch;

    var bookList = <Book>[];
    if (scope != ExportScope.wishlistOnly || format == ExportFormat.pdf) {
      final res = await _books.getAll();
      if (res.isLeft()) return left((res as Left<Failure, List<Book>>).value);
      bookList = res.getOrElse((_) => const <Book>[]);
    }
    var wishlistList = <WishlistBook>[];
    if (scope != ExportScope.libraryOnly && format != ExportFormat.pdf) {
      final res = await _wishlist.getAll();
      if (res.isLeft()) {
        return left((res as Left<Failure, List<WishlistBook>>).value);
      }
      wishlistList = res.getOrElse((_) => const <WishlistBook>[]);
    }
    final ymd = _ymd(stamp);

    switch (format) {
      case ExportFormat.json:
        return right(
          ExportResult(
            suggestedFileName: 'pitak-export-$ymd.json',
            mimeType: 'application/json',
            bytes: _utf8(
              _json.export(
                books: bookList,
                wishlist: wishlistList,
                exportedAt: stamp,
                libraryId: libraryId,
                libraryName: libraryName == 'My Library' ? '' : libraryName,
              ),
            ),
          ),
        );
      case ExportFormat.csv:
        return right(
          ExportResult(
            suggestedFileName: 'pitak-library-$ymd.csv',
            mimeType: 'text/csv',
            bytes: _utf8(_libraryCsv(bookList)),
          ),
        );
      case ExportFormat.pdf:
        // The PDF is ALWAYS the library list (a "book list" is the catalogue),
        // regardless of scope — mirrors Kotlin ExportUseCase.
        final selection = pdfColumns ?? PdfColumn.defaultSelection;
        final columns = resolvePrintColumns(selection, defaultPdfLabels());
        final bytes = await _pdf.render(
          libraryName: libraryName.trim().isEmpty ? 'My Library' : libraryName,
          books: bookList,
          columns: columns,
          footerAttribution: kPdfFooterAttribution,
          logoBytes: logoBytes,
          footerIconBytes: footerIconBytes,
          regularFonts: pdfRegularFonts,
          boldFonts: pdfBoldFonts,
          textRasterizer: textRasterizer,
        );
        return right(
          ExportResult(
            suggestedFileName: 'pitak-$ymd.pdf',
            mimeType: 'application/pdf',
            bytes: bytes,
          ),
        );
    }
  }

  /// Flat library CSV with a header row; values RFC4180-quoted.
  String _libraryCsv(List<Book> books) {
    const headers = [
      'title',
      'author',
      'isbn',
      'publisher',
      'publishedYear',
      'genre',
      'language',
      'pageCount',
      'location',
      'copyCount',
      'notes',
    ];
    final buf = StringBuffer()..writeln(headers.map(_csv).join(','));
    for (final b in books) {
      buf.writeln(
        [
          b.title,
          b.author ?? '',
          b.isbn ?? '',
          b.publisher ?? '',
          b.publishedYear?.toString() ?? '',
          b.genre ?? '',
          b.language ?? '',
          b.pageCount?.toString() ?? '',
          b.location ?? '',
          b.copyCount.toString(),
          b.notes ?? '',
        ].map(_csv).join(','),
      );
    }
    return buf.toString();
  }

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// RFC4180 field quoting: wrap in quotes and double internal quotes when the
  /// value contains a comma, quote, or newline.
  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// `YYYYMMDD` stamp for the file name.
  static String _ymd(int epochMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}$mm$dd';
  }
}

/// The Pitak attribution line drawn on every PDF page footer. Verbatim parity
/// with the Kotlin `pdf_footer_attribution` string.
const String kPdfFooterAttribution =
    'Book records are generated using Pitak, a free personal and community '
    'library software developed by Parallel Line Foundation';

/// Default English [PdfColumnLabels] for the PDF export.
///
/// Header labels mirror Kotlin `pdf_col_*`; enum labels reuse the app's
/// existing source-type / age-group wording; the date format matches Kotlin's
/// `d MMM yyyy` ("5 Jun 2026"). Kept here (application layer) so the pure
/// domain plan + infrastructure renderer stay locale-agnostic.
PdfColumnLabels defaultPdfLabels() => const PdfColumnLabels(
  header: {
    PdfColumn.title: 'Title',
    PdfColumn.author: 'Author',
    PdfColumn.year: 'Year',
    PdfColumn.isbn: 'ISBN',
    PdfColumn.publisher: 'Publisher',
    PdfColumn.genre: 'Genre',
    PdfColumn.language: 'Language',
    PdfColumn.pages: 'Pages',
    PdfColumn.ageGroup: 'Age group',
    PdfColumn.quantity: 'Qty',
    PdfColumn.addedDate: 'Date added',
    PdfColumn.location: 'Location',
    PdfColumn.source: 'Source',
    PdfColumn.sourceDetail: 'Source detail',
  },
  sourceType: _sourceTypeLabel,
  ageGroup: _ageGroupLabel,
  formatDate: _formatDate,
);

String _sourceTypeLabel(BookSourceType t) => switch (t) {
  BookSourceType.purchased => 'Purchased',
  BookSourceType.gift => 'Gift',
  BookSourceType.donated => 'Donated',
  BookSourceType.inherited => 'Inherited',
  BookSourceType.other => 'Other',
};

String _ageGroupLabel(AgeGroup g) => switch (g) {
  AgeGroup.above3 => 'Above 3',
  AgeGroup.above6 => 'Above 6',
  AgeGroup.above10 => 'Above 10',
  AgeGroup.above15 => 'Above 15',
  AgeGroup.advanced => 'Advanced',
};

const List<String> _monthAbbr = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `d MMM yyyy` (e.g. "5 Jun 2026"), matching Kotlin's PDF date format. A zero
/// epoch (no added-date recorded) renders blank.
String _formatDate(int epochMillis) {
  if (epochMillis <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
  return '${d.day} ${_monthAbbr[d.month - 1]} ${d.year}';
}
