import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../../support/a11y.dart';
import '../../support/fake_document_saver.dart';
import '../../support/fake_export_work_area.dart';
import '../../support/live_regions.dart';
import '../../support/pdf_ending_renderer.dart';
import '../periodicals/application/periodical_fakes.dart';

/// Captures what would be handed to the OS share sheet.
///
/// Since review finding P4-M6 (decision D172) an export is shared as a FILE
/// of the app's own, by its path. The bytes and the name the tests look at
/// are those of that file, read from the fake work area. This fake also
/// CARRIES the fake work area and the fake saver of its test, so that every
/// `ProviderScope` of this file wires the three together in one way.
class _FakeShare implements FileShareService {
  /// Where the controller puts the export's file.
  final FakeExportWorkArea workArea = FakeExportWorkArea();

  /// What "Save file" talks to.
  final FakeDocumentSaver saver = FakeDocumentSaver();

  String? fileName;
  String? mimeType;
  Uint8List? bytes;
  ShareOutcome outcome = ShareOutcome.success;

  /// When given, the share sheet "stays open" until it completes.
  Completer<void>? gate;

  @override
  Future<ShareOutcome> shareFile({
    required String path,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    bytes = workArea.files[path];
    fileName = path.split('/').last;
    this.mimeType = mimeType;
    await gate?.future;
    return outcome;
  }

  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();

  // D172: sharing BYTES made the share plugin write a copy that nobody
  // removes. The page's controller must never do it again.
  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();
}

/// A renderer that parks at a gate after reporting some progress, so the
/// page's in-flight UI (bar, counter, Cancel) can be inspected.
class _GatedRenderer implements LibraryPdfRenderer {
  Completer<void> gate = Completer<void>();
  bool sawCancel = false;

  // Every list fits: these tests are about the run, not about the count.
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
    int maxCachedTiles = PdfLibraryRenderer.defaultMaxCachedTiles,
  }) async => PdfSizeEstimate(
    objectsNeeded: 0,
    objectsAllowed: 1,
    rowsTotal: books.length,
    rowsThatFit: books.length,
  );

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
    onProgress?.call(
      const PdfRenderProgress(
        rowsDone: 0,
        rowsTotal: 200,
        pagesDone: 1,
        cachedTiles: 0,
      ),
    );
    onProgress?.call(
      const PdfRenderProgress(
        rowsDone: 50,
        rowsTotal: 200,
        pagesDone: 3,
        cachedTiles: 12,
      ),
    );
    await gate.future;
    if (cancelToken?.isCancelled ?? false) {
      sawCancel = true;
      throw const PdfRenderCancelled();
    }
    return Uint8List.fromList('%PDF-fake'.codeUnits);
  }
}

class _NoRaster implements PdfTextRasterizer {
  @override
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  }) async => null;
}

class _Books implements CatalogueItemRepository {
  _Books(this._books);

  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<CatalogueItem> _books;
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(_books);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(_books);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch ? const <CatalogueItem>[] : _books;
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
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String i) async =>
      right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

class _Wishlist implements WishlistRepository {
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
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String i) async =>
      right(null);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  testWidgets('CSV export hands its file to the share service', (tester) async {
    // The "Books to include" section pushes the button below the default
    // 800×600 viewport (a ListView never mounts off-screen children).
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final share = _FakeShare();
    final useCase = ExportLibraryUseCase(
      jsonEncoder: const PitakaJsonExporter(),
      pdfRenderer: const PdfLibraryRenderer(),
      bookRepo: _Books([
        const CatalogueItem(id: 1, title: 'Godaan', isbn: '111'),
      ]),
      wishlistRepo: _Wishlist(),
      periodicalRepo: FakePeriodicals(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
          fileShareServiceProvider.overrideWithValue(share),
          exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
          documentSaverProvider.overrideWithValue(share.saver),
        ],
        child: const MaterialApp(home: ExportPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select CSV (no fonts needed) then export.
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share file'));
    await tester.pumpAndSettle();

    // The fix: bytes reach the share sheet instead of silently vanishing.
    expect(share.bytes, isNotNull);
    expect(share.fileName, endsWith('.csv'));
    expect(share.mimeType, 'text/csv');
    expect(find.textContaining('Shared'), findsOneWidget);
  });

  group('source filter (Books to include)', () {
    const books = [
      CatalogueItem(
        id: 1,
        title: 'Godaan',
        sourceType: ItemSourceType.donated,
        sourceDetail: 'Ram Sharma',
      ),
      CatalogueItem(
        id: 2,
        title: 'Gaban',
        sourceType: ItemSourceType.donated,
        sourceDetail: 'Sita Devi',
      ),
      CatalogueItem(
        id: 3,
        title: 'Karmabhoomi',
        sourceType: ItemSourceType.purchased,
      ),
      CatalogueItem(id: 4, title: 'Sevasadan'),
    ];

    Future<_FakeShare> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final share = _FakeShare();
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books(books),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(share.saver),
            // The facet the picker lists — what the repository would return.
            for (final type in ItemSourceType.values)
              librarySourceDetailsProvider(type).overrideWith(
                (ref) async => switch (type) {
                  ItemSourceType.donated => const ['Ram Sharma', 'Sita Devi'],
                  _ => const <String>[],
                },
              ),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      return share;
    }

    List<String> csvTitles(_FakeShare share) => utf8
        .decode(share.bytes!)
        .trim()
        .split('\n')
        .skip(1)
        .map((l) => l.split(',').first)
        .toList();

    testWidgets('is hidden for JSON (a backup is always everything)', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Books to include'), findsNothing);
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Books to include'), findsOneWidget);
      expect(find.byKey(const Key('export-source-all')), findsOneWidget);
      // No type chosen yet: no detail picker.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('a type chip narrows the CSV and tags the file name', (
      tester,
    ) async {
      final share = await pump(tester);
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-source-donated')));
      await tester.pumpAndSettle();
      // Donor picker appears with the facet values + "Any".
      expect(
        find.byKey(const ValueKey('export-source-detail-donated')),
        findsOneWidget,
      );

      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();

      expect(share.fileName, startsWith('pitak-library-donated-'));
      expect(csvTitles(share), ['Godaan', 'Gaban']);
    });

    testWidgets("picking a donor exports only that donor's books", (
      tester,
    ) async {
      final share = await pump(tester);
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-source-donated')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('export-source-detail-donated')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sita Devi').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();

      expect(share.fileName, startsWith('pitak-library-donated-sita-devi-'));
      expect(csvTitles(share), ['Gaban']);
    });

    testWidgets('switching type drops the detail; a type with no details '
        'says so and still filters', (tester) async {
      final share = await pump(tester);
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-source-donated')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('export-source-detail-donated')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ram Sharma').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-source-purchased')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('export-source-detail-empty')),
        findsOneWidget,
      );

      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();
      expect(share.fileName, startsWith('pitak-library-purchased-'));
      expect(share.fileName, isNot(contains('ram-sharma')));
      expect(csvTitles(share), ['Karmabhoomi']);
    });

    testWidgets('"All sources" restores the full export', (tester) async {
      final share = await pump(tester);
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-source-donated')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-source-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();
      expect(share.fileName, startsWith('pitak-library-2'));
      expect(csvTitles(share), hasLength(4));
    });
  });

  group('N10-e — PDF progress + cancel on the page', () {
    /// The PDF column picker pushes the button (and the progress section
    /// under it) below the default 800×600 test viewport, where a ListView
    /// never mounts children. Use a phone-tall viewport instead.
    void tallViewport(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Future<_GatedRenderer> pumpPdfExport(
      WidgetTester tester,
      _FakeShare share,
    ) async {
      tallViewport(tester);
      final renderer = _GatedRenderer();
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: renderer,
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(share.saver),
            pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
            pdfTextFontsLoaderProvider.overrideWithValue(
              () async => (regular: <ByteData>[], bold: <ByteData>[]),
            ),
            pdfTextRasterizerProvider.overrideWithValue(_NoRaster()),
            exportLogoReaderProvider.overrideWith(
              (ref) async =>
                  (_) async => null,
            ),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share file'));
      // Not pumpAndSettle: the progress bar animates while the run is parked.
      await tester.pump();
      await tester.pump();
      return renderer;
    }

    testWidgets('shows a determinate bar, the counter and Cancel', (
      tester,
    ) async {
      final share = _FakeShare();
      final renderer = await pumpPdfExport(tester, share);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('export-progress')),
      );
      expect(bar.value, closeTo(0.25, 0.001));
      expect(find.text('Rendering page 3 · 50 of 200 books'), findsOneWidget);
      expect(find.byKey(const Key('export-cancel')), findsOneWidget);
      // The export button is disabled while running.
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share file'),
      );
      expect(button.onPressed, isNull);

      // Finish the run: progress UI goes away, success copy appears.
      renderer.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-progress')), findsNothing);
      expect(find.byKey(const Key('export-cancel')), findsNothing);
      expect(find.textContaining('Shared'), findsOneWidget);
      expect(share.fileName, endsWith('.pdf'));
    });

    testWidgets('tapping Cancel ends the run with safe copy and no share', (
      tester,
    ) async {
      final share = _FakeShare();
      final renderer = await pumpPdfExport(tester, share);

      await tester.tap(find.byKey(const Key('export-cancel')));
      await tester.pump();
      // The renderer only observes the token at its next boundary.
      renderer.gate.complete();
      await tester.pumpAndSettle();

      expect(renderer.sawCancel, isTrue);
      expect(share.bytes, isNull);
      expect(find.text('Export cancelled.'), findsOneWidget);
      expect(find.byKey(const Key('export-progress')), findsNothing);
      // Ready for another go.
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share file'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('leaving and returning mid-run shows the live run', (
      tester,
    ) async {
      tallViewport(tester);
      final share = _FakeShare();
      final renderer = _GatedRenderer();
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: renderer,
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(share.saver),
            pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
            pdfTextFontsLoaderProvider.overrideWithValue(
              () async => (regular: <ByteData>[], bold: <ByteData>[]),
            ),
            pdfTextRasterizerProvider.overrideWithValue(_NoRaster()),
            exportLogoReaderProvider.overrideWith(
              (ref) async =>
                  (_) async => null,
            ),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share file'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('export-cancel')), findsOneWidget);

      // Pop while the render is parked, then come back.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const ExportPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The run survived (controller keep-alive): the page shows it live.
      expect(find.byKey(const Key('export-cancel')), findsOneWidget);
      expect(find.text('Rendering page 3 · 50 of 200 books'), findsOneWidget);

      renderer.gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Shared'), findsOneWidget);
      expect(share.fileName, endsWith('.pdf'));
    });
  });

  // Review finding P4-M6 (decisions D165 to D170, D172 and D176): the page
  // has two buttons where "Export to file" stood. Both make the export
  // first; "Save file" then hands its file to the app's own saver.
  group('P4-M6: Save file and Share file', () {
    /// Shows the page with one book and, unless [csv] is false, CSV chosen
    /// (no fonts needed for it).
    Future<void> pumpCsvPage(
      WidgetTester tester,
      _FakeShare share, {
      bool csv = true,
    }) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(share.saver),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      if (!csv) return;
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
    }

    Finder saveButton() => find.widgetWithText(FilledButton, 'Save file');
    Finder shareButton() => find.widgetWithText(OutlinedButton, 'Share file');

    bool? buttonsEnabled(WidgetTester tester) {
      final save = tester.widget<FilledButton>(saveButton());
      final share = tester.widget<OutlinedButton>(shareButton());
      return save.enabled == share.enabled ? save.enabled : null;
    }

    testWidgets('two buttons, Save first, and under them a note that says '
        'what kind of file an export is', (tester) async {
      // With JSON chosen, as the page opens. (With CSV or PDF the three
      // "Include" choices are switched off, and Flutter's contrast check
      // counts their greyed-out words: a thing of the page as it was, not
      // of the two buttons.)
      await pumpCsvPage(tester, _FakeShare(), csv: false);

      expect(saveButton(), findsOneWidget);
      expect(shareButton(), findsOneWidget);
      expect(find.text('Export to file'), findsNothing);
      expect(
        tester.getTopLeft(saveButton()).dy,
        lessThan(tester.getTopLeft(shareButton()).dy),
      );
      final note = find.text(
        'The export is an ordinary file: whoever can open the place you put '
        'it can read what is in it.',
      );
      expect(note, findsOneWidget);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(shareButton()).dy),
      );
      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets("Save file: the export's file goes to the saver, and the "
        'page says under which name it was saved', (tester) async {
      final share = _FakeShare();
      share.saver.result = FakeDocumentSaver.saved(
        name: 'pitak-library-20261122 (1).csv',
      );
      await pumpCsvPage(tester, share);

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(share.saver.paths, [share.workArea.lastPath]);
      expect(share.saver.paths.single, endsWith('.csv'));
      expect(share.bytes, isNull, reason: 'the share sheet is not asked');
      expect(
        find.text('Saved as pitak-library-20261122 (1).csv.'),
        findsOneWidget,
      );
      expect(share.workArea.discarded, [share.workArea.lastPath]);
      expect(buttonsEnabled(tester), isTrue);
    });

    testWidgets('without a name from the place the sentence ends after '
        '"Saved"', (tester) async {
      final share = _FakeShare();
      share.saver.result = FakeDocumentSaver.saved(name: '');
      await pumpCsvPage(tester, share);

      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(find.text('Saved.'), findsOneWidget);
      expect(find.textContaining('Saved as'), findsNothing);
    });

    const endings = <String, (DocumentSaveResult, String)>{
      'the save window was left': (
        DocumentSaveCancelled(),
        'No place was chosen, so nothing was saved.',
      ),
      'the place could not take the file, and nothing was left behind': (
        DocumentSaveNotSaved(),
        'The file could not be saved there. Nothing was left behind. Check '
            'the free storage of that place, or choose another, and try '
            'again.',
      ),
      'an unfinished file could not be taken back': (
        DocumentSaveLeftBehind(),
        'The file could not be saved there. An unfinished file may be left '
            'at that place; delete it. Then try again.',
      ),
      'the file chosen already has something in it (D176)': (
        DocumentSaveNotEmpty(),
        'That file already has something in it, so it was left as it is. '
            'Choose a new name in the save window and try again.',
      ),
      'the place cannot confirm that the file is stored (D183)': (
        DocumentSaveUnconfirmed(),
        'That place cannot confirm that a file is stored, so nothing was '
            'saved there. Choose a place on this phone or on a memory card, '
            'or use Share instead.',
      ),
      'this device has no save window (D171)': (
        DocumentSaveUnavailable(),
        'Saving to a file is not available on this device.',
      ),
      "the export's file was gone before it could be copied": (
        DocumentSaveSourceGone(),
        'Export failed.',
      ),
      'a mistake in code on either side of the channel': (
        DocumentSaveFailed(),
        'Export failed.',
      ),
    };
    for (final MapEntry(key: title, value: (result, sentence))
        in endings.entries) {
      testWidgets('not saved: $title', (tester) async {
        final share = _FakeShare();
        share.saver.result = result;
        await pumpCsvPage(tester, share);

        await tester.tap(saveButton());
        await tester.pumpAndSettle();

        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining('Saved'), findsNothing);
        expect(find.textContaining('Shared'), findsNothing);
        expect(share.workArea.discarded, [share.workArea.lastPath]);
        expect(buttonsEnabled(tester), isTrue);
      });
    }

    // Decision D193: the sentence of a finished run is drawn by its KIND,
    // as on the Create backup page: a success in the theme's main colour, a
    // window that was left plainly, a failure in the error colour. Until
    // then every sentence looked the same, and "An unfinished file may be
    // left at that place; delete it." looked like "Saved as NAME.".
    group('D193: the sentence is drawn by how the run ended', () {
      /// The colour the sentence [text] is drawn in.
      Color? colourOf(WidgetTester tester, String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      /// The page's theme, read where the sentence [text] stands.
      ThemeData themeAt(WidgetTester tester, String text) =>
          Theme.of(tester.element(find.text(text)));

      testWidgets('saved: in the main colour of the theme', (tester) async {
        const sentence = 'Saved as pitak-library-20261122.csv.';
        final share = _FakeShare();
        share.saver.result = FakeDocumentSaver.saved(
          name: 'pitak-library-20261122.csv',
        );
        await pumpCsvPage(tester, share);

        await tester.tap(saveButton());
        await tester.pumpAndSettle();

        final scheme = themeAt(tester, sentence).colorScheme;
        expect(colourOf(tester, sentence), scheme.primary);
      });

      for (final MapEntry(key: title, value: (result, sentence))
          in endings.entries) {
        // The first row of the table is not a failure: nothing went wrong,
        // the user left the window.
        final leftTheWindow = result is DocumentSaveCancelled;
        final how = leftTheWindow ? 'plain' : 'in the error colour';
        testWidgets('$title: $how', (tester) async {
          final share = _FakeShare();
          share.saver.result = result;
          await pumpCsvPage(tester, share);

          await tester.tap(saveButton());
          await tester.pumpAndSettle();

          final theme = themeAt(tester, sentence);
          final plain = theme.textTheme.bodyMedium?.color;
          // The three colours differ in this theme; otherwise the checks
          // below could pass for the wrong one.
          expect({
            plain,
            theme.colorScheme.primary,
            theme.colorScheme.error,
          }, hasLength(3));
          expect(
            colourOf(tester, sentence),
            leftTheWindow ? plain : theme.colorScheme.error,
          );
        });
      }

      testWidgets('a share sheet that was left: plain', (tester) async {
        const sentence =
            'Nothing was shared. If no app on that list could take the '
            'file, use Save file.';
        final share = _FakeShare()..outcome = ShareOutcome.dismissed;
        await pumpCsvPage(tester, share);

        await tester.tap(shareButton());
        await tester.pumpAndSettle();

        final theme = themeAt(tester, sentence);
        expect(colourOf(tester, sentence), theme.textTheme.bodyMedium?.color);
      });
    });

    testWidgets('a share sheet that is left gets a sentence (D170)', (
      tester,
    ) async {
      final share = _FakeShare()..outcome = ShareOutcome.dismissed;
      await pumpCsvPage(tester, share);

      await tester.tap(shareButton());
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Nothing was shared. If no app on that list could take the file, '
          'use Save file.',
        ),
        findsOneWidget,
      );
      expect(share.workArea.discarded, [share.workArea.lastPath]);
    });

    testWidgets('while the file is being saved the row reads "Saving…", '
        'its bar has no numbers, and there is no Cancel', (tester) async {
      final gate = Completer<void>();
      final share = _FakeShare();
      final saver = FakeDocumentSaver(gate: gate);
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(saver),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();

      await tester.tap(saveButton());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(saver.paths, hasLength(1), reason: 'the saver is asked');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('export-progress-label')))
            .data,
        'Saving…',
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('export-progress')),
      );
      expect(bar.value, isNull);
      expect(find.byKey(const Key('export-cancel')), findsNothing);
      expect(buttonsEnabled(tester), isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-progress')), findsNothing);
      expect(find.textContaining('Saved as'), findsOneWidget);
      expect(buttonsEnabled(tester), isTrue);
    });

    testWidgets('while the share sheet is open the row keeps its words, its '
        'bar has no numbers, and there is no Cancel', (tester) async {
      final gate = Completer<void>();
      final share = _FakeShare()..gate = gate;
      await pumpCsvPage(tester, share);

      await tester.tap(shareButton());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(share.fileName, isNotNull, reason: 'the share sheet is asked');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('export-progress-label')))
            .data,
        'Preparing export…',
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('export-progress')),
      );
      expect(bar.value, isNull);
      expect(find.byKey(const Key('export-cancel')), findsNothing);
      expect(find.text('Saving…'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Shared'), findsOneWidget);
    });
  });

  // Decision D177 (after the first look on a device): with PDF chosen the
  // page is longer than the screen, and "Saved as …" lay below it. The page
  // brings the sentence of a finished run into view by itself.
  group('D177: the sentence of a finished run is brought into view', () {
    /// Shows the page with CSV chosen, [saver] behind "Save file".
    Future<void> pumpPage(
      WidgetTester tester,
      _FakeShare share,
      FakeDocumentSaver saver,
    ) async {
      tester.view
        ..physicalSize = const Size(400, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(saver),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
    }

    bool onScreen(WidgetTester tester, Finder finder) {
      if (finder.evaluate().isEmpty) return false;
      final rect = tester.getRect(finder);
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      return rect.top >= kToolbarHeight && rect.bottom <= height;
    }

    /// Taps the button with [label]. While the run is held at [gate] the
    /// screen is cut off just under that button, so that everything below
    /// it (and the sentence to come) lies BELOW the screen; then the run is
    /// let go. The button's place is measured, not guessed.
    Future<void> finishRunWithTheButtonAtTheBottomEdge(
      WidgetTester tester,
      String label,
      Completer<void> gate,
    ) async {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final bottom = tester.getRect(find.text(label)).bottom + 16;
      tester.view.physicalSize = Size(400, bottom);
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
    }

    testWidgets('after a save, "Saved as …" is on the screen', (tester) async {
      final gate = Completer<void>();
      final share = _FakeShare();
      final saver = FakeDocumentSaver(gate: gate);
      await pumpPage(tester, share, saver);

      await finishRunWithTheButtonAtTheBottomEdge(tester, 'Save file', gate);

      expect(saver.paths, hasLength(1));
      expect(onScreen(tester, find.textContaining('Saved as')), isTrue);
    });

    testWidgets('a share sheet that was left: its sentence is on the '
        'screen', (tester) async {
      final gate = Completer<void>();
      final share = _FakeShare()
        ..outcome = ShareOutcome.dismissed
        ..gate = gate;
      await pumpPage(tester, share, FakeDocumentSaver());

      await finishRunWithTheButtonAtTheBottomEdge(tester, 'Share file', gate);

      expect(
        onScreen(tester, find.textContaining('Nothing was shared')),
        isTrue,
      );
    });
  });

  // Decision D190 (the review stop of P4-M6): the sentence of a finished
  // export is a "live region", so that a screen reader reads it out when it
  // appears. What is asked here is what a screen reader is GIVEN; that it
  // speaks is its own side and is seen on a device only.
  group('D190, for a screen reader: the result of a run is read out when '
      'it appears', () {
    /// Shows the page with CSV chosen, [saver] behind "Save file".
    Future<void> pumpPage(
      WidgetTester tester,
      _FakeShare share,
      FakeDocumentSaver saver,
    ) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: const PdfLibraryRenderer(),
        bookRepo: _Books([const CatalogueItem(id: 1, title: 'Godaan')]),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(saver),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
    }

    testWidgets('after a save, "Saved as …" is a live region of its own: '
        'that sentence and nothing else of the page', (tester) async {
      final handle = tester.ensureSemantics();
      final saver = FakeDocumentSaver(
        result: FakeDocumentSaver.saved(name: 'pitak-library-20261122.csv'),
      );
      await pumpPage(tester, _FakeShare(), saver);
      // Before a run there is no sentence, and nothing to read out.
      expect(liveRegionLabels(tester), isEmpty);

      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();

      // Exactly the sentence: the note under the buttons ("The export is
      // an ordinary file: …") stands just above it and is NOT part of it.
      expect(liveRegionLabels(tester), [
        'Saved as pitak-library-20261122.csv.',
      ]);
      handle.dispose();
    });

    testWidgets('a share sheet that was left: its sentence is a live '
        'region', (tester) async {
      const nothingShared =
          'Nothing was shared. If no app on that list could take the file, '
          'use Save file.';
      final handle = tester.ensureSemantics();
      final share = _FakeShare()..outcome = ShareOutcome.dismissed;
      await pumpPage(tester, share, FakeDocumentSaver());

      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();

      expect(liveRegionLabels(tester), [nothingShared]);
      handle.dispose();
    });

    testWidgets('while the file is being saved nothing is a live region: '
        'not the note, not "Saving…", and not the sentence of the run '
        'before', (tester) async {
      final handle = tester.ensureSemantics();
      // The save is held while its file is being copied.
      final gate = Completer<void>();
      final saver = FakeDocumentSaver(gate: gate);
      final share = _FakeShare()..outcome = ShareOutcome.dismissed;
      await pumpPage(tester, share, saver);

      // A first run, the Share way, leaves its sentence on the page.
      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();
      expect(liveRegionLabels(tester), hasLength(1));

      await tester.tap(find.text('Save file'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('export-progress-label')))
            .data,
        'Saving…',
      );
      expect(liveRegionLabels(tester), isEmpty);

      // The second run's sentence is a region again: built anew, read anew.
      gate.complete();
      await tester.pumpAndSettle();
      expect(liveRegionLabels(tester), [
        'Saved as ${FakeDocumentSaver.savedName}.',
      ]);
      handle.dispose();
    });
  });

  // Review finding P3-B2 (ADR 0033; decisions D209, D212 and D213): a PDF
  // that cannot be made used to end as "Export failed.", after a long wait
  // and with no word on why or on what to do. Now a list that is too long
  // for one PDF is counted first and gets a sentence with its numbers, and
  // a run that ran out of memory gets one too. Both sentences were approved
  // word for word.
  group('P3-B2: a PDF that cannot be made says why', () {
    const tooLong =
        'This list is too long for one PDF: it has 6 books, and about 4 fit. '
        'Titles and names in scripts such as Devanagari or Tamil are drawn '
        'as pictures, and a PDF can hold only so many. Narrow the list under '
        '"Books to include", choose fewer columns, or export CSV instead. '
        'Nothing was exported.';
    const outOfMemory =
        'This phone ran out of memory for the PDF. Nothing was exported. '
        'Narrow the list under "Books to include", or export CSV instead.';

    /// Shows the page with six books, chooses PDF and taps [button]. The
    /// run ends at once: [renderer] does not wait.
    Future<_FakeShare> runPdfExport(
      WidgetTester tester,
      EndingPdfRenderer renderer,
      String button,
    ) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final share = _FakeShare();
      final useCase = ExportLibraryUseCase(
        jsonEncoder: const PitakaJsonExporter(),
        pdfRenderer: renderer,
        bookRepo: _Books(
          List.generate(6, (i) => CatalogueItem(id: i + 1, title: 'Book $i')),
        ),
        wishlistRepo: _Wishlist(),
        periodicalRepo: FakePeriodicals(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            exportWorkAreaProvider.overrideWith((ref) async => share.workArea),
            documentSaverProvider.overrideWithValue(share.saver),
            pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
            pdfTextFontsLoaderProvider.overrideWithValue(
              () async => (regular: <ByteData>[], bold: <ByteData>[]),
            ),
            pdfTextRasterizerProvider.overrideWithValue(_NoRaster()),
            exportLogoReaderProvider.overrideWith(
              (ref) async =>
                  (_) async => null,
            ),
          ],
          child: const MaterialApp(home: ExportPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return share;
    }

    final endings = <String, (EndingPdfRenderer Function(), String)>{
      'a list of 6 books of which 4 fit': (
        () => EndingPdfRenderer(rowsThatFit: 4),
        tooLong,
      ),
      'a run that ran out of memory': (
        () => EndingPdfRenderer(renderError: const OutOfMemoryError()),
        outOfMemory,
      ),
    };
    for (final MapEntry(key: title, value: (make, sentence))
        in endings.entries) {
      for (final button in ['Save file', 'Share file']) {
        testWidgets('$title, after "$button": its sentence, as a failure, '
            'read out; no file anywhere; the page ready again', (tester) async {
          final handle = tester.ensureSemantics();
          final renderer = make();
          final share = await runPdfExport(tester, renderer, button);

          // The sentence, and nothing of the plain one.
          expect(find.text(sentence), findsOneWidget);
          expect(find.text('Export failed.'), findsNothing);
          // Drawn as a failure (D193), and read out when it appears (D190).
          final theme = Theme.of(tester.element(find.text(sentence)));
          expect(
            theme.colorScheme.error,
            isNot(theme.textTheme.bodyMedium?.color),
          );
          expect(
            tester.widget<Text>(find.text(sentence)).style?.color,
            theme.colorScheme.error,
          );
          expect(liveRegionLabels(tester), [sentence]);
          // What the sentence sends the user to is on this page, under
          // these very words.
          expect(find.text('Books to include'), findsOneWidget);
          expect(find.text('PDF columns'), findsOneWidget);
          expect(find.text('CSV'), findsOneWidget);
          // No file was made, and nobody was handed one.
          expect(share.workArea.files, isEmpty);
          expect(share.bytes, isNull);
          expect(share.saver.paths, isEmpty);
          // The run is over: no bar, no Cancel, both buttons live again.
          expect(find.byKey(const Key('export-progress')), findsNothing);
          expect(find.byKey(const Key('export-cancel')), findsNothing);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save file'),
                )
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Share file'),
                )
                .enabled,
            isTrue,
          );
          handle.dispose();
        });
      }
    }

    testWidgets('a list that is too long is not drawn at all', (tester) async {
      final renderer = EndingPdfRenderer(rowsThatFit: 4);
      await runPdfExport(tester, renderer, 'Save file');

      expect(renderer.measureCalls, 1);
      expect(renderer.renderCalls, 0);
    });

    testWidgets('a PDF that can be made is made as before', (tester) async {
      final renderer = EndingPdfRenderer();
      final share = await runPdfExport(tester, renderer, 'Share file');

      expect(renderer.renderCalls, 1);
      expect(find.textContaining('Shared'), findsOneWidget);
      expect(share.fileName, endsWith('.pdf'));
    });
  });
}
