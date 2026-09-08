import 'dart:convert';
import 'dart:typed_data';

// Transitive dependency of file_selector; imported only for the picker seam
// below (it also re-exports XFile). Deliberately NOT added to pubspec so the
// dependency surface stays unchanged (same seam as restore_page_test.dart).
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

class _MemBookRepo implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<Book> stored = [];
  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    stored.add(book);
    return right(book);
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

class _MemWishlistRepo implements WishlistRepository {
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

/// Picker seam (M05): an in-memory file whose REPORTED length can lie.
class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector(this.bytes, {this.reportedLength});
  final Uint8List bytes;
  final int? reportedLength;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(bytes, name: 'pick', length: reportedLength);
}

void main() {
  Widget page(ImportLibraryUseCase useCase) => ProviderScope(
    overrides: [
      importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
      // Library/Wishlist controllers refresh on success — give them repos.
      bookRepositoryProvider.overrideWith((ref) async => _MemBookRepo()),
      wishlistRepositoryProvider.overrideWith(
        (ref) async => _MemWishlistRepo(),
      ),
    ],
    child: const MaterialApp(home: ImportPage()),
  );

  ImportLibraryUseCase useCaseWith(_MemBookRepo books) => ImportLibraryUseCase(
    jsonParser: const PitakaJsonImporter(),
    bookRepo: books,
    wishlistRepo: _MemWishlistRepo(),
  );

  group('M05: picked files are read under a cap', () {
    final smallJson = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 3,
          'exportedAt': 0,
          'books': [
            {'title': 'From file', 'isbn': '888'},
          ],
          'wishlist': <dynamic>[],
        }),
      ),
    );

    testWidgets('a text pick reporting > maxTextChars is refused unread', (
      tester,
    ) async {
      final books = _MemBookRepo();
      FileSelectorPlatform.instance = _FakeFileSelector(
        smallJson,
        reportedLength: 5 * 1024 * 1024 * 1024,
      );
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.text('File is too large to import safely.'), findsOneWidget);
      expect(find.text('Import complete'), findsNothing);
      expect(books.stored, isEmpty, reason: 'nothing may reach the use case');
    });

    testWidgets('a ZIP pick reporting > maxArchiveBytes is refused unread', (
      tester,
    ) async {
      // ZIP magic so the archive cap (not the text cap) applies; reported
      // size far past it. Old code skipped the size guard for ZIPs entirely.
      final zipish = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      final books = _MemBookRepo();
      FileSelectorPlatform.instance = _FakeFileSelector(
        zipish,
        reportedLength: 5 * 1024 * 1024 * 1024,
      );
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.text('File is too large to import safely.'), findsOneWidget);
      expect(books.stored, isEmpty);
    });

    testWidgets('an honest small text pick still imports', (tester) async {
      final books = _MemBookRepo();
      FileSelectorPlatform.instance = _FakeFileSelector(smallJson);
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.text('File is too large to import safely.'), findsNothing);
      expect(find.text('Import complete'), findsOneWidget);
      expect(books.stored.single.title, 'From file');
    });
  });

  testWidgets('pasting JSON and tapping Import shows a summary', (
    tester,
  ) async {
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
          // Library/Wishlist controllers refresh on success — give them repos.
          bookRepositoryProvider.overrideWith((ref) async => _MemBookRepo()),
          wishlistRepositoryProvider.overrideWith(
            (ref) async => _MemWishlistRepo(),
          ),
        ],
        child: const MaterialApp(home: ImportPage()),
      ),
    );
    await tester.pumpAndSettle();

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'Imported', 'isbn': '999'},
      ],
      'wishlist': <dynamic>[],
    });

    await tester.enterText(find.byType(TextField), json);
    await tester.tap(find.text('Import text'));
    await tester.pumpAndSettle();

    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Books added: 1'), findsOneWidget);
  });
}
