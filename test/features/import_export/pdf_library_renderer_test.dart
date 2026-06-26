import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart'
    show defaultPdfLabels, kPdfFooterAttribution;
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_fonts.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

void main() {
  // Asset loading (fonts) needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const renderer = PdfLibraryRenderer();

  List<PrintColumn> cols() =>
      resolvePrintColumns(PdfColumn.defaultSelection, defaultPdfLabels());

  // The bundled Latin + Devanagari faces are enough to exercise the resolver.
  Future<PdfFontBundle> regular() async => [
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
  ];
  Future<PdfFontBundle> bold() async => [
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
  ];

  // A rendered PDF must start with the "%PDF-" magic.
  void expectValidPdf(List<int> bytes) {
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  }

  test('renders an empty library to a valid PDF', () async {
    final bytes = await renderer.render(
      libraryName: 'My Library',
      books: const [],
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('renders a small Latin library to a valid PDF', () async {
    final books = [
      const Book(title: 'A Book', author: 'An Author', copyCount: 2),
      const Book(title: 'Another', isbn: '978-1', publishedYear: 2020),
    ];
    final bytes = await renderer.render(
      libraryName: 'Test Lib',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('renders Devanagari (Hindi) titles without throwing', () async {
    // This is the exact failure case that crashed Helvetica (Latin-1 only).
    final books = [
      const Book(title: 'भारत: गांधी के बाद', author: 'Ramachandra Guha'),
      const Book(title: 'गोदान', author: 'प्रेमचंद'),
    ];
    final bytes = await renderer.render(
      libraryName: 'मेरी लाइब्रेरी',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('paginates a large library without throwing', () async {
    final books = List.generate(
      200,
      (i) => Book(title: 'Book number $i', author: 'Author $i'),
    );
    final bytes = await renderer.render(
      libraryName: 'Big Library',
      books: books,
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      boldFonts: await bold(),
    );
    expectValidPdf(bytes);
  });

  test('a bad logo/icon is skipped, not fatal', () async {
    final bytes = await renderer.render(
      libraryName: 'Lib',
      books: const [Book(title: 'X')],
      columns: cols(),
      footerAttribution: kPdfFooterAttribution,
      regularFonts: await regular(),
      logoBytes: Uint8List.fromList([1, 2, 3, 4]),
      footerIconBytes: Uint8List.fromList([5, 6, 7, 8]),
    );
    expectValidPdf(bytes);
  });
}
