import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal repo so the app shell can boot without a real database in tests
/// (the full Library behaviour is covered in library_page_test.dart).
class _EmptyRepo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      BookPage(items: rows.sublist(start, end), hasMore: end < rows.length),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

void main() {
  testWidgets('app boots to the Library screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _EmptyRepo(),
          ),
        ],
        child: const PitakaApp(),
      ),
    );
    // The app now opens on a ~1s branding splash before the Library; advance
    // past the splash timer (the biometric gate is off by default).
    await tester.pump(); // first frame (splash)
    await tester.pump(const Duration(seconds: 2)); // fire the splash timer
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
