import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

class _MemBookRepo implements BookRepository {
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

void main() {
  testWidgets('pasting JSON and tapping Import shows a summary', (
    tester,
  ) async {
    final useCase = ImportLibraryUseCase(
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
