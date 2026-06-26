import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal repo so the app shell can boot without a real database in tests
/// (the full Library behaviour is covered in library_page_test.dart).
class _EmptyRepo implements BookRepository {
  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
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
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
}

void main() {
  testWidgets('app boots to the Library screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
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
