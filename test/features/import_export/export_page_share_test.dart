import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Captures what would be handed to the OS share sheet.
class _FakeShare implements FileShareService {
  String? fileName;
  String? mimeType;
  Uint8List? bytes;
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
    this.mimeType = mimeType;
    return outcome;
  }
}

class _Books implements BookRepository {
  _Books(this._books);
  final List<Book> _books;
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_books);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(_books);
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
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String i) async => right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
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
    final share = _FakeShare();
    final useCase = ExportLibraryUseCase(
      bookRepo: _Books([const Book(id: 1, title: 'Godaan', isbn: '111')]),
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
}
