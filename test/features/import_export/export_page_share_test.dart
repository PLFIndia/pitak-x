import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Captures what would be handed to the OS share sheet.
class _FakeShare implements FileShareService {
  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();

  String? fileName;
  String? mimeType;
  Uint8List? bytes;
  ShareOutcome outcome = ShareOutcome.success;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    this.bytes = bytes;
    this.fileName = fileName;
    this.mimeType = mimeType;
    return outcome;
  }
}

/// A renderer that parks at a gate after reporting some progress, so the
/// page's in-flight UI (bar, counter, Cancel) can be inspected.
class _GatedRenderer implements LibraryPdfRenderer {
  Completer<void> gate = Completer<void>();
  bool sawCancel = false;

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

class _Books implements BookRepository {
  _Books(this._books);

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
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
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch ? const <CatalogueItem>[] : _books;
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      BookPage(items: rows.sublist(start, end), hasMore: end < rows.length),
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
  testWidgets('CSV export hands bytes to the share service', (tester) async {
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
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
          fileShareServiceProvider.overrideWithValue(share),
        ],
        child: const MaterialApp(home: ExportPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select CSV (no fonts needed) then export.
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export to file'));
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
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
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

      await tester.tap(find.text('Export to file'));
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

      await tester.tap(find.text('Export to file'));
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

      await tester.tap(find.text('Export to file'));
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

      await tester.tap(find.text('Export to file'));
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
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
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
      await tester.tap(find.text('Export to file'));
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
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export to file'),
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
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export to file'),
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
      );
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exportLibraryUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(share),
            pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
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
      await tester.tap(find.text('Export to file'));
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
}
