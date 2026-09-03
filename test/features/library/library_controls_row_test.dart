import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Two languages; `query` honours the language facet like the real repo.
class _Repo implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  static const all = [
    Book(title: 'Godaan', language: 'Hindi'),
    Book(title: 'Dune', language: 'English'),
  ];
  int queryCalls = 0;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(all);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(all);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async {
    queryCalls++;
    return right(
      language == null
          ? all
          : all.where((b) => b.language == language).toList(),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const ['English', 'Hindi']);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book b) async => right(b);
  @override
  Future<Either<Failure, Book>> update(Book b) async => right(b);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

void main() {
  late _Repo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _Repo();
    container = ProviderContainer(
      overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilterChip chip(WidgetTester tester, String label) =>
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

  // Regression (review 2026-09-03, Blocker): the chips read the filter from a
  // mutable field on the LibraryController notifier, which never triggered a
  // rebuild — the list narrowed but the chip never looked selected and the
  // "Clear" chip never appeared, so the user could not see or undo a filter.
  testWidgets('tapping a language chip selects it, narrows the list, and '
      'offers Clear', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(chip(tester, 'Hindi').selected, isFalse);
    expect(find.text('Clear'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();

    expect(chip(tester, 'Hindi').selected, isTrue);
    expect(chip(tester, 'English').selected, isFalse);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(container.read(libraryLanguageFilterProvider), 'Hindi');
  });

  testWidgets('Clear removes the filter and restores the full list', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'English'));
    await tester.pumpAndSettle();
    expect(find.text('Godaan'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear'), findsNothing);
    expect(chip(tester, 'English').selected, isFalse);
    expect(find.text('Godaan'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(container.read(libraryLanguageFilterProvider), isNull);
  });

  testWidgets('tapping the selected chip again clears it', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Hindi'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'Hindi').selected, isFalse);
    expect(find.text('Dune'), findsOneWidget);
  });

  test('LibraryLanguageFilter treats blank as "no filter"', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(libraryLanguageFilterProvider.notifier).set('  ');
    expect(c.read(libraryLanguageFilterProvider), isNull);
    c.read(libraryLanguageFilterProvider.notifier).set(' Hindi ');
    expect(c.read(libraryLanguageFilterProvider), 'Hindi');
    c.read(libraryLanguageFilterProvider.notifier).clear();
    expect(c.read(libraryLanguageFilterProvider), isNull);
  });
}
