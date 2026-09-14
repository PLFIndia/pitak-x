import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShare implements FileShareService {
  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();

  Uint8List? bytes;
  String? fileName;
  ShareOutcome outcome = ShareOutcome.success;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    this.bytes = bytes;
    this.fileName = fileName;
    return outcome;
  }
}

/// A renderer that reports one row at a time and waits at a gate the test
/// opens, so the controller's mid-run state and its cancel path can be
/// observed deterministically. Honours the cancel token like the real one.
class _GatedRenderer implements LibraryPdfRenderer {
  _GatedRenderer({this.rows = 100});

  final int rows;

  /// Completed by the test to let the next row through.
  Completer<void> gate = Completer<void>();

  /// Completed by the renderer when it is parked at the gate.
  Completer<void> parked = Completer<void>();
  int renderCalls = 0;
  int rowsRendered = 0;

  void release() {
    final g = gate;
    gate = Completer<void>();
    parked = Completer<void>();
    g.complete();
  }

  @override
  Future<Uint8List> render({
    required String libraryName,
    required List<Book> books,
    required List<PrintColumn> columns,
    required String footerAttribution,
    PdfFontBundle regularFonts = const [],
    PdfFontBundle boldFonts = const [],
    Uint8List? logoBytes,
    Uint8List? footerIconBytes,
    PdfTextRasterizer? textRasterizer,
    PdfRenderProgressListener? onProgress,
    RenderCancelToken? cancelToken,
    int maxCachedTiles = PdfLibraryRenderer.defaultMaxCachedTiles,
  }) async {
    renderCalls += 1;
    PdfRenderProgress at(int done) => PdfRenderProgress(
      rowsDone: done,
      rowsTotal: rows,
      pagesDone: 1 + done ~/ 30,
      cachedTiles: 0,
    );
    onProgress?.call(at(0));
    for (var r = 1; r <= rows; r++) {
      cancelToken?.throwIfCancelled();
      if (!parked.isCompleted) parked.complete();
      await gate.future;
      rowsRendered = r;
      onProgress?.call(at(r));
    }
    return Uint8List.fromList('%PDF-fake'.codeUnits);
  }
}

class _Books implements BookRepository {
  _Books(this._books, {this.failWith});

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<Book> _books;
  final Failure? failWith;

  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
      failWith != null ? left(failWith!) : right(_books);
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <Book>[]
        : (await getAll()).getOrElse((_) => const []);
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
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Book>> insert(Book b) async => right(b);
  @override
  Future<Either<Failure, Book>> update(Book b) async => right(b);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String i) async => right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer({
    required BookRepository books,
    required _FakeShare share,
    LibraryPdfRenderer pdfRenderer = const PdfLibraryRenderer(),
  }) {
    final container = ProviderContainer(
      overrides: [
        exportLibraryUseCaseProvider.overrideWith(
          (ref) async => ExportLibraryUseCase(
            jsonEncoder: const PitakaJsonExporter(),
            pdfRenderer: pdfRenderer,
            bookRepo: books,
            wishlistRepo: _Wishlist(),
          ),
        ),
        fileShareServiceProvider.overrideWithValue(share),
        // The PDF path needs the footer icon + rasterizer providers; in a
        // pure test neither the asset bundle nor an engine is wanted.
        pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
        pdfTextRasterizerProvider.overrideWithValue(_NoRaster()),
        exportLogoReaderProvider.overrideWith(
          (ref) async =>
              (_) async => null,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Pumps the event loop until [renderer] is parked at its gate.
  Future<void> untilParked(_GatedRenderer renderer) => renderer.parked.future;

  test('JSON export shares bytes and mints a library ID', () async {
    final share = _FakeShare();
    final container = makeContainer(
      books: _Books([const Book(id: 1, title: 'Godaan')]),
      share: share,
    );

    final result = await container
        .read(exportControllerProvider.notifier)
        .export(scope: ExportScope.both, format: ExportFormat.json);

    expect(result.outcome, ExportOutcome.shared);
    expect(result.fileName, endsWith('.json'));
    final payload =
        jsonDecode(utf8.decode(share.bytes!)) as Map<String, dynamic>;
    // D40: every JSON export carries a minted 32-hex library ID.
    expect(payload['libraryId'], matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test(
    'a repository failure maps to ExportOutcome.failed, nothing shared',
    () async {
      final share = _FakeShare();
      final container = makeContainer(
        books: _Books(const [], failWith: const StorageFailure('read failed')),
        share: share,
      );

      final result = await container
          .read(exportControllerProvider.notifier)
          .export(scope: ExportScope.libraryOnly, format: ExportFormat.csv);

      expect(result.outcome, ExportOutcome.failed);
      expect(share.bytes, isNull);
    },
  );

  test('a dismissed share sheet reports dismissed (not an error)', () async {
    final share = _FakeShare()..outcome = ShareOutcome.dismissed;
    final container = makeContainer(books: _Books(const []), share: share);

    final result = await container
        .read(exportControllerProvider.notifier)
        .export(scope: ExportScope.libraryOnly, format: ExportFormat.csv);

    expect(result.outcome, ExportOutcome.dismissed);
  });

  group('N10-e — progress, cancel, one run at a time', () {
    test('state goes idle → running(progress) → finished(shared)', () async {
      final share = _FakeShare();
      final renderer = _GatedRenderer(rows: 60);
      final container = makeContainer(
        books: _Books([const Book(id: 1, title: 'A')]),
        share: share,
        pdfRenderer: renderer,
      );
      final states = <ExportUiState>[];
      container.listen<ExportUiState>(
        exportControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      expect(states.single, isA<ExportIdle>());

      final run = container
          .read(exportControllerProvider.notifier)
          .export(scope: ExportScope.libraryOnly, format: ExportFormat.pdf);
      await untilParked(renderer);
      expect(container.read(exportControllerProvider), isA<ExportRunning>());
      expect(container.read(exportControllerProvider.notifier).isRunning, true);

      // Let every row through.
      for (var r = 0; r < 60; r++) {
        renderer.release();
        await Future<void>.delayed(Duration.zero);
      }
      final result = await run;
      expect(result.outcome, ExportOutcome.shared);
      expect(share.bytes, isNotNull);

      final running = states.whereType<ExportRunning>().toList();
      // Throttled: 60 rows publish the 0/25/50 marks and the final 60, not
      // one state per row.
      final reported = running
          .map((s) => s.progress?.rowsDone)
          .whereType<int>()
          .toList();
      expect(reported, [0, 25, 50, 60]);
      for (var i = 1; i < reported.length; i++) {
        expect(reported[i], greaterThan(reported[i - 1]));
      }
      final last = states.last;
      expect(last, isA<ExportFinished>());
      expect((last as ExportFinished).result.outcome, ExportOutcome.shared);
      expect(
        container.read(exportControllerProvider.notifier).isRunning,
        isFalse,
      );
    });

    test('cancel mid-render → cancelled, nothing shared, run ends', () async {
      final share = _FakeShare();
      final renderer = _GatedRenderer();
      final container = makeContainer(
        books: _Books([const Book(id: 1, title: 'A')]),
        share: share,
        pdfRenderer: renderer,
      );
      final notifier = container.read(exportControllerProvider.notifier);
      final run = notifier.export(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
      );
      await untilParked(renderer);
      renderer.release();
      await untilParked(renderer);
      renderer.release();
      await untilParked(renderer);
      expect(renderer.rowsRendered, 2);

      notifier.cancel();
      renderer.release(); // the renderer wakes, sees the token, throws

      final result = await run;
      expect(result.outcome, ExportOutcome.cancelled);
      expect(share.bytes, isNull, reason: 'a cancelled run shares nothing');
      expect(renderer.rowsRendered, lessThanOrEqualTo(3));
      final state = container.read(exportControllerProvider);
      expect(state, isA<ExportFinished>());
      expect((state as ExportFinished).result.outcome, ExportOutcome.cancelled);
      expect(notifier.isRunning, false);
    });

    test('cancel before the render starts still ends cancelled', () async {
      final share = _FakeShare();
      final renderer = _GatedRenderer(rows: 10);
      final container = makeContainer(
        books: _Books([const Book(id: 1, title: 'A')]),
        share: share,
        pdfRenderer: renderer,
      );
      final notifier = container.read(exportControllerProvider.notifier);
      final run = notifier.export(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
      );
      // Cancel synchronously, before any await inside the run has resumed.
      notifier.cancel();
      final result = await run;
      expect(result.outcome, ExportOutcome.cancelled);
      expect(share.bytes, isNull);
      // Either the pre-render check or the renderer's first row boundary
      // stopped it; no row was rendered.
      expect(renderer.rowsRendered, 0);
    });

    test('a second export while running joins the in-flight run', () async {
      final share = _FakeShare();
      final renderer = _GatedRenderer(rows: 3);
      final container = makeContainer(
        books: _Books([const Book(id: 1, title: 'A')]),
        share: share,
        pdfRenderer: renderer,
      );
      final notifier = container.read(exportControllerProvider.notifier);
      final first = notifier.export(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
      );
      await untilParked(renderer);
      final second = notifier.export(
        scope: ExportScope.both,
        format: ExportFormat.json, // ignored: the running PDF wins
      );
      expect(identical(first, second), isTrue);

      for (var r = 0; r < 3; r++) {
        renderer.release();
        await Future<void>.delayed(Duration.zero);
      }
      final a = await first;
      final b = await second;
      expect(a.outcome, ExportOutcome.shared);
      expect(identical(a, b), isTrue);
      expect(renderer.renderCalls, 1, reason: 'exactly one render');
      expect(share.fileName, endsWith('.pdf'));

      // Once finished, a new export starts a fresh run.
      final third = notifier.export(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.csv,
      );
      expect(identical(first, third), isFalse);
      expect((await third).outcome, ExportOutcome.shared);
      expect(share.fileName, endsWith('.csv'));
    });

    test(
      'losing the last listener mid-run keeps the run and its terminal state',
      () async {
        final share = _FakeShare();
        final renderer = _GatedRenderer(rows: 2);
        final container = makeContainer(
          books: _Books([const Book(id: 1, title: 'A')]),
          share: share,
          pdfRenderer: renderer,
        );
        final sub = container.listen<ExportUiState>(
          exportControllerProvider,
          (_, _) {},
        );
        final run = container
            .read(exportControllerProvider.notifier)
            .export(scope: ExportScope.libraryOnly, format: ExportFormat.pdf);
        await untilParked(renderer);

        // The page is popped: its listener goes away while rows are pending.
        sub.close();
        await container.pump();

        renderer.release();
        await untilParked(renderer);
        renderer.release();
        final result = await run;
        expect(result.outcome, ExportOutcome.shared);

        // Coming back to the page sees the finished state, not a reset.
        final state = container.read(exportControllerProvider);
        expect(state, isA<ExportFinished>());
        expect((state as ExportFinished).result.outcome, ExportOutcome.shared);
      },
    );

    test('the real renderer + the use case honour a cancel token', () async {
      // End-to-end through the REAL renderer (no gate): cancel after the
      // first progress report and expect the typed outcome, no share.
      final share = _FakeShare();
      final books = List.generate(
        400,
        (i) => Book(id: i + 1, title: 'Row $i', author: 'A $i'),
      );
      late ExportController notifier;
      final container = ProviderContainer(
        overrides: [
          exportLibraryUseCaseProvider.overrideWith(
            (ref) async => ExportLibraryUseCase(
              jsonEncoder: const PitakaJsonExporter(),
              pdfRenderer: const PdfLibraryRenderer(),
              bookRepo: _Books(books),
              wishlistRepo: _Wishlist(),
            ),
          ),
          fileShareServiceProvider.overrideWithValue(share),
          pdfFooterIconLoaderProvider.overrideWithValue(() async => null),
          pdfTextRasterizerProvider.overrideWithValue(_NoRaster()),
          exportLogoReaderProvider.overrideWith(
            (ref) async =>
                (_) async => null,
          ),
        ],
      );
      addTearDown(container.dispose);
      notifier = container.read(exportControllerProvider.notifier);
      container.listen<ExportUiState>(exportControllerProvider, (_, next) {
        if (next is ExportRunning && (next.progress?.rowsDone ?? 0) >= 25) {
          notifier.cancel();
        }
      });
      final result = await notifier.export(
        scope: ExportScope.libraryOnly,
        format: ExportFormat.pdf,
      );
      expect(result.outcome, ExportOutcome.cancelled);
      expect(share.bytes, isNull);
    });
  });
}

/// A rasterizer that never produces a tile (Latin `drawString` path), so the
/// real renderer runs without a Flutter engine in a plain `test()`.
class _NoRaster implements PdfTextRasterizer {
  @override
  Future<RasterizedText?> raster(
    String text, {
    required double fontSize,
    required bool bold,
    required int colorArgb,
  }) async => null;
}
