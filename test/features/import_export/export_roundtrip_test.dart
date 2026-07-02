import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

class _Books implements BookRepository {
  _Books(this._all);
  final List<Book> _all;
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(_all);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
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
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
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
    Book(
      title: 'भारत: गांधी के बाद',
      author: 'Ramachandra Guha',
      isbn: '978-1',
      ageGroup: AgeGroup.advanced,
      sourceType: BookSourceType.gift,
      language: 'Hindi',
      copyCount: 3,
      addedDate: 100,
      removed: true,
      removedAt: 200,
      addedBy: 'Khoj',
    ),
    Book(title: 'Plain', addedDate: 50),
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
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
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
    expect(payload.books.length, 2);
    expect(payload.wishlist.length, 1);

    final b = payload.books.firstWhere((x) => x.isbn == '978-1');
    expect(b.title, 'भारत: गांधी के बाद');
    expect(b.author, 'Ramachandra Guha');
    expect(b.ageGroup, AgeGroup.advanced);
    expect(b.sourceType, BookSourceType.gift);
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
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
    );
    final result = await useCase(
      scope: ExportScope.libraryOnly,
      format: ExportFormat.json,
    );
    final export = result.getOrElse((f) => fail('failed: $f'));
    final payload = const PitakaJsonImporter().parse(utf8.decode(export.bytes));
    expect(payload.books.length, 2);
    expect(payload.wishlist, isEmpty);
  });

  test('CSV export has a header and one row per book', () async {
    final useCase = ExportLibraryUseCase(
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
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

  test('PDF export produces a valid PDF of the library list', () async {
    final useCase = ExportLibraryUseCase(
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
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
      bookRepo: _Books(books),
      wishlistRepo: _Wishlist(wishlist),
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

  test('exporter omits null fields but keeps required ones', () {
    final json = const PitakaJsonExporter().export(
      books: const [Book(title: 'Only')],
      wishlist: const [],
      exportedAt: 1,
    );
    expect(json, contains('"title": "Only"'));
    expect(json, isNot(contains('"author"')));
    expect(json, contains('"schemaVersion": 3'));
  });

  test('exporter emits libraryId/libraryName the importer reads back', () {
    const exporter = PitakaJsonExporter();
    final json = exporter.export(
      books: const [Book(title: 'B')],
      wishlist: const [],
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
      books: const [Book(title: 'B')],
      wishlist: const [],
      exportedAt: 1,
    );
    expect(json, isNot(contains('"libraryId"')));
    expect(json, isNot(contains('"libraryName"')));
  });
}
