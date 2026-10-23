import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Empty series store: the card's cover-fallback map
/// (`periodicalCoversProvider`, S14) reads `listAll`; the tests below use
/// books, so the map stays empty.
class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  Widget host(CatalogueItem book, {bool unavailable = false}) => ProviderScope(
    overrides: [
      periodicalRepositoryProvider.overrideWith(
        (ref) async => _NoPeriodicals(),
      ),
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

  testWidgets('shows the copy-count pill when copyCount > 1', (tester) async {
    await tester.pumpWidget(
      host(const CatalogueItem(title: 'Dune', copyCount: 4)),
    );
    await tester.pump();
    expect(find.text('×4'), findsOneWidget);
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
    expect(find.text('×12'), findsOneWidget);
  });
}
