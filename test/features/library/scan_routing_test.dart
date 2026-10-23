/// S14 widget tests for the quick-add scan routing (`routeScannedBarcode` in
/// `library_page.dart`): the page switches on the sealed `ScanRoute` the
/// use case returned (S34 + ADR 0013 D11) —
///
/// - `OpenCataloguedItem` offers the EXISTING item instead of an add form the
///   UNIQUE isbn index would only refuse at save time;
/// - `AddBookByIsbn` opens the pre-filled add form (a failed read falls
///   through here too — the save path and the index still guard duplicates);
/// - `AddIssueOfPeriodical` / `AddPeriodicalByIssn` push the S16 forms (the
///   add-issue form with the scanned series preselected, the series form
///   with the scanned ISSN pre-filled).
///
/// The camera itself is not exercised here: `ScannerPage` is a thin
/// flutter_zxing wrapper, and the routing under test is what happens AFTER a
/// scan result comes back. The use case's own tests
/// (`route_scanned_barcode_use_case_test.dart`) cover the barcode→route
/// mapping; these tests cover the route→navigation mapping only.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';

/// In-memory item repo fake: enough for the pages pushed by the routing
/// (CatalogueItemDetailPage reads through `catalogueItemByIdProvider` → this
/// repo) and for the use case's ISBN lookup.
class _MemItems implements CatalogueItemRepository {
  _MemItems(this.books);

  final List<CatalogueItem> books;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      right(books.where((b) => b.id == id).firstOrNull);

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async => right(CatalogueItemPage(items: books, hasMore: false));

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(
        isbn.trim().isEmpty
            ? null
            : books.where((b) => b.isbn == isbn).firstOrNull,
      );

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(books);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

/// Minimal periodical repo fake: the use case's ISSN lookup is what the scan
/// routing exercises; `listAll`/`issuesOf` answer for the pushed add-issue
/// form (its series picker + cadence prefill read them).
class _MemPeriodicals implements PeriodicalRepository {
  _MemPeriodicals(this.periodicals);

  final List<Periodical> periodicals;

  @override
  Future<Either<Failure, Periodical?>> findByIssn(String issn) async =>
      right(periodicals.where((p) => p.issn == issn).firstOrNull);

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async => right([
    for (final p in periodicals)
      PeriodicalSummary(periodical: p, issueCount: 0),
  ]);

  @override
  Future<Either<Failure, List<CatalogueItem>>> issuesOf(
    String periodicalUid,
  ) async => right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

const _existing = CatalogueItem(
  id: 7,
  itemUid: 'uid-7',
  title: 'Dune',
  isbn: '9780441172719',
);

/// 9771 is a real ISSN block prefix; `1234-5679` has a valid check digit.
const _series = Periodical(id: 3, periodicalUid: 'per-3', title: 'Weekly');

/// A home route with one button that runs the post-scan routing on the REAL
/// use case (over the fakes), the way `_quickAddByScan` does once the
/// scanner popped a barcode.
Widget _host({
  required _MemItems items,
  required _MemPeriodicals periodicals,
  required String coversDir,
  required String scanned,
}) => ProviderScope(
  overrides: [
    catalogueItemRepositoryProvider.overrideWith((ref) async => items),
    periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
    coversDirProvider.overrideWith((ref) async => coversDir),
    // The pushed add-issue form builds PeriodicalsController, whose build
    // arms the real 60 s timer — pinned so the tests settle.
    nowTickProvider.overrideWith((ref) => 0),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                final useCase = await ref.read(
                  routeScannedBarcodeUseCaseProvider.future,
                );
                if (!context.mounted) return;
                await routeScannedBarcode(context, useCase, scanned);
              },
              child: const Text('scan'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_routing_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget host(
    _MemItems items, {
    required String scanned,
    List<Periodical> periodicals = const [],
  }) => _host(
    items: items,
    periodicals: _MemPeriodicals(periodicals),
    coversDir: tmp.path,
    scanned: scanned,
  );

  testWidgets('a catalogued ISBN offers the EXISTING book, not the add form', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_MemItems([_existing]), scanned: _existing.isbn!),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    expect(
      find.text("'Dune' is already in your library."),
      findsOneWidget,
      reason: 'the dialog names the existing book',
    );
    expect(find.byType(AddBookPage), findsNothing);

    await tester.tap(find.text('View book'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogueItemDetailPage), findsOneWidget);
    expect(find.text('Dune'), findsWidgets, reason: 'detail header rendered');
  });

  testWidgets('Cancel closes the dialog without navigating', (tester) async {
    await tester.pumpWidget(
      host(_MemItems([_existing]), scanned: _existing.isbn!),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsNothing);
    expect(find.byType(CatalogueItemDetailPage), findsNothing);
  });

  testWidgets('an unknown ISBN opens the add form pre-filled', (tester) async {
    await tester.pumpWidget(host(_MemItems([]), scanned: '9780140449136'));

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    expect(find.byType(AddBookPage), findsOneWidget);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'ISBN'),
    );
    expect(field.controller?.text, '9780140449136');
  });

  testWidgets('a magazine barcode of a KNOWN series routes to the add-issue '
      'form with the series preselected (D11)', (tester) async {
    // The 977 EAN-13 carrying the series' ISSN 1234-5679 (check digit 3).
    const scanned = '9771234567003';
    await tester.pumpWidget(
      host(
        _MemItems([]),
        periodicals: [_series.copyWith(issn: '1234-5679')],
        scanned: scanned,
      ),
    );

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    final page = tester.widget<AddIssuePage>(find.byType(AddIssuePage));
    expect(
      page.periodical?.periodicalUid,
      'per-3',
      reason: 'the scanned series travels to the add-issue form',
    );
    // The picker settled on the preselected series.
    expect(find.text('Weekly'), findsWidgets);
  });

  testWidgets('a magazine barcode with NO matching series routes to the '
      'series form with the ISSN pre-filled (D11)', (tester) async {
    await tester.pumpWidget(host(_MemItems([]), scanned: '9771234567003'));

    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();

    final page = tester.widget<PeriodicalFormPage>(
      find.byType(PeriodicalFormPage),
    );
    expect(page.initialIssn, '1234-5679');
    // And the ISSN field shows the scanned value.
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, '1234-5679'),
    );
    expect(field.controller?.text, '1234-5679');
  });
}
