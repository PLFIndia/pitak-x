import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart'
    show defaultPdfLabels;
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

void main() {
  // Rasterization uses dart:ui (a live engine), so the binding is required.
  TestWidgetsFlutterBinding.ensureInitialized();

  const regular = ['assets/fonts/NotoSansDevanagari-Regular.ttf'];
  const bold = ['assets/fonts/NotoSansDevanagari-Bold.ttf'];

  test('rasterizer shapes a Devanagari conjunct into a PNG tile', () async {
    final r = UiPdfTextRasterizer(regularAssets: regular, boldAssets: bold);
    // बच्चे — the च्च conjunct is exactly what drawString cannot shape.
    final tile = await r.raster(
      'बच्चे',
      fontSize: 12,
      bold: false,
      colorArgb: 0xFF000000,
    );
    expect(tile, isNotNull);
    expect(tile!.pngBytes, isNotEmpty);
    // PNG magic bytes.
    expect(tile.pngBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(tile.widthPt, greaterThan(0));
    expect(tile.heightPt, greaterThan(0));
  });

  test('empty string yields no tile', () async {
    final r = UiPdfTextRasterizer(regularAssets: regular, boldAssets: bold);
    expect(
      await r.raster('', fontSize: 12, bold: false, colorArgb: 0xFF000000),
      isNull,
    );
  });

  test('renderer embeds shaped Hindi text and produces a valid PDF', () async {
    final r = UiPdfTextRasterizer(regularAssets: regular, boldAssets: bold);
    final columns = resolvePrintColumns(
      PdfColumn.defaultSelection,
      defaultPdfLabels(),
    );
    final bytes = await const PdfLibraryRenderer().render(
      libraryName: 'पुस्तकालय',
      books: const [Book(id: 1, title: 'बच्चे की कहानी', author: 'प्रेमचंद')],
      columns: columns,
      footerAttribution: 'Pitak',
      textRasterizer: r,
    );
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
