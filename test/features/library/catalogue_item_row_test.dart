import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_row.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Answers `listAll` with series summaries; the row's series-cover fallback
/// (W4) reads only that. Everything else is unimplemented on purpose.
class _MemPeriodicals implements PeriodicalRepository {
  _MemPeriodicals(this.periodicals);

  final List<Periodical> periodicals;

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async => right([
    for (final p in periodicals)
      PeriodicalSummary(periodical: p, issueCount: 0),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  /// The `ItemCover` the row under test rendered — the resolved cover
  /// reference (own vs series fallback, W4) is visible on its `coverUrl`.
  ItemCover rowCover(WidgetTester tester) => tester.widget<ItemCover>(
    find.descendant(
      of: find.byType(CatalogueItemRow),
      matching: find.byType(ItemCover),
    ),
  );

  /// Hosts the row inside a ProviderScope with [periodicals] answering the
  /// series-cover map (`periodicalCoversProvider` → `listAll`).
  Widget host(
    CatalogueItem book, {
    bool unavailable = false,
    List<Periodical> periodicals = const [],
  }) => ProviderScope(
    overrides: [
      periodicalRepositoryProvider.overrideWith(
        (ref) async => _MemPeriodicals(periodicals),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CatalogueItemRow(
          book: book,
          unavailable: unavailable,
          onTap: () {},
        ),
      ),
    ),
  );

  testWidgets('shows the "Not available" badge when unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Hobbit'), unavailable: true),
    );
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('no availability badge when available', (tester) async {
    await tester.pumpWidget(host(const CatalogueItem(title: 'Hobbit')));
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('a removed book shows Removed, not Not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', removed: true),
        unavailable: true,
      ),
    );
    expect(find.text('Removed'), findsOneWidget);
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('long title + multiple badges does not overflow a narrow row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        const CatalogueItem(
          title: 'An Extremely Long Book Title That On Its Own Fills The Row',
          author: 'A Long Author Name As Well',
          copyCount: 99,
          needsMetadata: true,
        ),
        unavailable: true,
      ),
    );
    // No RenderFlex overflow exception thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('Needs info'), findsOneWidget);
    expect(find.text('×99'), findsOneWidget);
  });

  // S14 (ADR 0013 U1): kind badges classify non-book rows; books (the
  // default kind) carry no badge.
  group('kind badges (S14)', () {
    testWidgets('a book row shows no kind badge', (tester) async {
      await tester.pumpWidget(host(const CatalogueItem(title: 'Hobbit')));
      expect(find.text('Issue'), findsNothing);
      expect(find.text('Bound volume'), findsNothing);
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('a magazine issue row shows "Issue"', (tester) async {
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Weekly 2026-10',
            details: IssueOf(periodicalUid: 'per-1', issueNumber: 12),
          ),
        ),
      );
      expect(find.text('Issue'), findsOneWidget);
      expect(find.text('Bound volume'), findsNothing);
    });

    testWidgets('a bound volume row shows "Bound volume"', (tester) async {
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Weekly 2026 H2',
            details: IssueOf(
              periodicalUid: 'per-1',
              issueDate: 1751328000000, // 2025-07-01T00:00:00Z
              boundUntil: 1767225600000, // 2026-01-01
            ),
          ),
        ),
      );
      expect(find.text('Bound volume'), findsOneWidget);
      expect(find.text('Issue'), findsNothing);
    });

    testWidgets('an other-kind row shows "Other"', (tester) async {
      await tester.pumpWidget(
        host(const CatalogueItem(title: 'Road atlas', details: OtherItemOf())),
      );
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('an issue with its own cover does not ask the series map', (
      tester,
    ) async {
      // The row must keep the issue's OWN cover reference; a seeded series
      // cover must not replace it (W4: own cover wins).
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Weekly 2026-10',
            coverUrl: 'covers/own.jpg',
            details: IssueOf(periodicalUid: 'per-1', issueNumber: 12),
          ),
          periodicals: const [
            Periodical(
              id: 1,
              periodicalUid: 'per-1',
              title: 'Weekly',
              coverUrl: 'covers/series.jpg',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // The rendered cover widget was given the issue's OWN reference.
      expect(rowCover(tester).coverUrl, 'covers/own.jpg');
    });

    testWidgets('an issue with NO cover falls back to the series cover', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Weekly 2026-10',
            details: IssueOf(periodicalUid: 'per-1', issueNumber: 12),
          ),
          periodicals: const [
            Periodical(
              id: 1,
              periodicalUid: 'per-1',
              title: 'Weekly',
              coverUrl: 'covers/series.jpg',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // W4 fallback: the series cover stands in for the issue.
      expect(rowCover(tester).coverUrl, 'covers/series.jpg');
    });
  });
}
