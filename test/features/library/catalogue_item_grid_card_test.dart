import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';
import 'package:pitaka/features/library/presentation/widgets/shelf_location_line.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// In-memory series store for the card's cover-fallback map
/// (`periodicalCoversProvider`, S14). Empty for the book-only tests.
class _MemPeriodicals implements PeriodicalRepository {
  _MemPeriodicals(this.periodicals);

  final List<Periodical> periodicals;

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async => right([
    for (final periodical in periodicals)
      PeriodicalSummary(periodical: periodical, issueCount: 0),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  Widget host(
    CatalogueItem book, {
    bool unavailable = false,
    int copiesOut = 0,
    List<Periodical> periodicals = const [],
  }) => ProviderScope(
    overrides: [
      periodicalRepositoryProvider.overrideWith(
        (ref) async => _MemPeriodicals(periodicals),
      ),
      coversDirProvider.overrideWith((ref) async => '.'),
    ],
    child: MaterialApp(
      home: Scaffold(
        // A fixed, realistic grid-cell box so overflow would actually throw.
        body: Center(
          child: SizedBox(
            width: 180,
            height: 280,
            child: CatalogueItemGridCard(
              book: book,
              unavailable: unavailable,
              copiesOut: copiesOut,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('renders title and author', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'The Hobbit', author: 'Tolkien')),
    );
    await tester.pump();
    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Tolkien'), findsOneWidget);
  });

  testWidgets('shows the shelf location as the last text line', (tester) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Hobbit', author: 'Tolkien', location: 'A3'),
      ),
    );
    expect(find.text('A3'), findsOneWidget);
    // The tappable parent merges its children's labels into one node, so
    // match the fragment, not the whole label.
    expect(find.bySemanticsLabel(RegExp('Shelf location: A3')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf line tone follows the pill rule (removed never red)', (
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

  testWidgets('shows the copy-count pill when copyCount > 1', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Dune', copyCount: 4)),
    );
    await tester.pump();
    expect(find.text('Copies: 4'), findsOneWidget);
  });

  testWidgets('the copies pill counts copies out on loan', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Dune', copyCount: 4), copiesOut: 1),
    );
    await tester.pump();
    expect(find.text('Copies: 4 · 1 out'), findsOneWidget);
  });

  testWidgets('not available: no pill; red shelf line with the out icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Dune', location: 'A3'),
        unavailable: true,
      ),
    );
    await tester.pump();
    expect(find.text('Not available'), findsNothing);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
  });

  testWidgets('not available with no shelf set shows the fallback line', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Dune'), unavailable: true),
    );
    await tester.pump();
    expect(find.text('Not available'), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
  });

  testWidgets('line caps: title 3, author 2', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Dune', author: 'Herbert')),
    );
    await tester.pump();
    expect(tester.widget<Text>(find.text('Dune')).maxLines, 3);
    expect(tester.widget<Text>(find.text('Herbert')).maxLines, 2);
  });

  testWidgets('a removed book shows Removed, not Not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(title: 'Old Tales', removed: true),
        unavailable: true,
      ),
    );
    await tester.pump();
    expect(find.text('Removed'), findsOneWidget);
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('an inherited grid cover remains periodical-owned', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CatalogueItem(
          id: 7,
          title: 'Weekly — No 1',
          details: IssueOf(periodicalUid: 'per-1', issueNumber: 1),
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

    final cover = tester.widget<ItemCover>(find.byType(ItemCover));
    expect(cover.coverUrl, 'covers/series.jpg');
    expect(cover.owner, CoverOwners.periodical('per-1'));
  });

  testWidgets('every status pill at once does not overflow the cell', (
    tester,
  ) async {
    // needsMetadata + unavailable + copyCount, with a very long title — the
    // worst case for the fixed-height grid cell.
    await tester.pumpWidget(
      host(
        const CatalogueItem(
          title: 'A Tremendously Long Book Title That Would Wrap Many Lines',
          author: 'An Equally Long Author Name For Good Measure',
          location: 'Back room, second cupboard, third shelf from the top',
          copyCount: 12,
          needsMetadata: true,
        ),
        unavailable: true,
      ),
    );
    await tester.pump();
    // No RenderFlex/overflow exception was thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('Needs info'), findsOneWidget);
    expect(find.text('Copies: 12'), findsOneWidget);
  });
}
