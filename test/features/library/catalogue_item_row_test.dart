import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_row.dart';
import 'package:pitaka/features/library/presentation/widgets/shelf_location_line.dart';
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
    int copiesOut = 0,
    List<Periodical> periodicals = const [],
    double textScale = 1,
  }) => ProviderScope(
    overrides: [
      periodicalRepositoryProvider.overrideWith(
        (ref) async => _MemPeriodicals(periodicals),
      ),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        // The library list's own horizontal padding.
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CatalogueItemRow(
            book: book,
            unavailable: unavailable,
            copiesOut: copiesOut,
            onTap: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('not available: no pill; the shelf line turns red with the out '
      'icon', (tester) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', location: 'A3'),
        unavailable: true,
      ),
    );
    // The library has no availability pill any more (published pages do).
    expect(find.text('Not available'), findsNothing);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
    expect(find.byIcon(Icons.shelves), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Shelf location: A3, not available')),
      findsOneWidget,
    );
  });

  testWidgets('not available with no shelf set still says so', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Hobbit'), unavailable: true),
    );
    expect(find.text('Not available'), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
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

  testWidgets('shows the shelf location under the author', (tester) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', author: 'Tolkien', location: 'A3'),
      ),
    );
    expect(find.text('A3'), findsOneWidget);
    // The tappable parent merges its children's labels into one node, so
    // match the fragment, not the whole label.
    expect(find.bySemanticsLabel(RegExp('Shelf location: A3')), findsOneWidget);
  });

  testWidgets('shelf line tone follows the badge rule (removed never red)', (
    tester,
  ) async {
    ShelfLocationTone tone() =>
        tester.widget<ShelfLocationLine>(find.byType(ShelfLocationLine)).tone;

    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Hobbit', location: 'A3')),
    );
    expect(tone(), ShelfLocationTone.normal);

    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', location: 'A3'),
        unavailable: true,
      ),
    );
    expect(tone(), ShelfLocationTone.unavailable);

    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', location: 'A3', removed: true),
        unavailable: true,
      ),
    );
    expect(tone(), ShelfLocationTone.removed);
  });

  testWidgets('no shelf line when the location is unset', (tester) async {
    await tester.pumpWidget(host(const CatalogueItem(title: 'Hobbit')));
    expect(find.byIcon(Icons.shelves), findsNothing);
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
          location: 'Back room, second cupboard, third shelf from the top',
          copyCount: 99,
          needsMetadata: true,
        ),
        unavailable: true,
      ),
    );
    // No RenderFlex overflow exception thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('Needs info'), findsOneWidget);
    expect(find.text('Copies: 99'), findsOneWidget);
  });

  // 2026-11-09 text-fit redesign: full-width text, 3 / 2 line caps and one
  // wrapping bottom line (shelf, pills, copies).
  group('text fit', () {
    const longTitle =
        'The Remarkable and Extraordinarily Long History of Indian Libraries';
    const longAuthor = 'Shiyali Ramamrita Ranganathan and Krishna Kumar';

    Future<void> phone(
      WidgetTester tester, {
      Size size = const Size(412, 915),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    // Regression: the badge column used to be a Flexible beside the text's
    // Expanded, so the text got half the free space (156 of 380 px) even
    // with no badges at all.
    testWidgets('the text uses the full width beside the cover', (
      tester,
    ) async {
      await phone(tester);
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: longTitle,
            author: longAuthor,
            copyCount: 3,
            needsMetadata: true,
          ),
        ),
      );
      final row = tester.getSize(find.byType(CatalogueItemRow)).width;
      final title = tester.getSize(find.text(longTitle)).width;
      expect(title / row, greaterThan(0.75), reason: '$title of $row');
    });

    testWidgets('title up to 3 lines, author up to 2', (tester) async {
      await tester.pumpWidget(
        host(const CatalogueItem(title: longTitle, author: longAuthor)),
      );
      expect(tester.widget<Text>(find.text(longTitle)).maxLines, 3);
      expect(tester.widget<Text>(find.text(longAuthor)).maxLines, 2);
    });

    // Test-font note: in widget tests every glyph is a square as wide as the
    // font size (about twice a real font's average), so these texts are
    // sized for THAT font. At the full ~312 px width this title takes 3
    // lines and the author 2; at the old half width (156 px) they needed 6
    // and 4 and were cut — so this is a real regression check.
    testWidgets('title and author fit their caps at full width (the old half '
        'width cut them)', (tester) async {
      await phone(tester);
      const title = 'Libraries of India and the people who built them';
      const author = 'Ranganathan and Krishna Kumar';
      await tester.pumpWidget(
        host(const CatalogueItem(title: title, author: author)),
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(title))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(author))
            .didExceedMaxLines,
        isFalse,
      );
    });

    testWidgets('a short shelf and a pill share one line', (tester) async {
      await phone(tester);
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Dune',
            location: 'A3',
            needsMetadata: true,
          ),
        ),
      );
      final shelfY = tester.getCenter(find.text('A3')).dy;
      expect(tester.getCenter(find.text('Needs info')).dy, closeTo(shelfY, 4));
    });

    testWidgets('a short shelf and the copies label share one line', (
      tester,
    ) async {
      await phone(tester);
      await tester.pumpWidget(
        host(const CatalogueItem(title: 'Dune', location: 'A3', copyCount: 2)),
      );
      final shelfY = tester.getCenter(find.text('A3')).dy;
      expect(tester.getCenter(find.text('Copies: 2')).dy, closeTo(shelfY, 4));
    });

    testWidgets('a long shelf takes its own line and the pills move below', (
      tester,
    ) async {
      await phone(tester);
      const shelf = 'Back room, second cupboard, third shelf from the top';
      await tester.pumpWidget(
        host(
          const CatalogueItem(
            title: 'Dune',
            location: shelf,
            needsMetadata: true,
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Needs info')).dy,
        greaterThan(tester.getBottomLeft(find.text(shelf)).dy - 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('copies: "Copies: 3 · 1 out" while some copies are out', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const CatalogueItem(title: 'Dune', copyCount: 3), copiesOut: 1),
      );
      expect(find.text('Copies: 3 · 1 out'), findsOneWidget);
      // One copy is still on the shelf: not "not available".
      expect(find.byIcon(Icons.outbox), findsNothing);
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('everything at once on a small phone at ${scale}x text '
          'does not overflow', (tester) async {
        await phone(tester, size: const Size(320, 900));
        await tester.pumpWidget(
          host(
            const CatalogueItem(
              title: longTitle,
              author: longAuthor,
              location: 'Back room, second cupboard, third shelf from the top',
              copyCount: 12,
              needsMetadata: true,
              details: IssueOf(periodicalUid: 'p', issueNumber: 1),
            ),
            unavailable: true,
            copiesOut: 12,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Copies: 12 · 12 out'), findsOneWidget);
      });
    }
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
      expect(rowCover(tester).owner, CoverOwners.item(0));
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
      expect(
        rowCover(tester).owner,
        CoverOwners.periodical('per-1'),
        reason: 'an inherited cover remains periodical-owned',
      );
    });
  });
}
