import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/presentation/widgets/book_grid_card.dart';

void main() {
  Widget host(Book book, {bool unavailable = false}) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        // A fixed, realistic grid-cell box so overflow would actually throw.
        body: Center(
          child: SizedBox(
            width: 180,
            height: 280,
            child: BookGridCard(
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
      host(const Book(title: 'The Hobbit', author: 'Tolkien')),
    );
    await tester.pump();
    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Tolkien'), findsOneWidget);
  });

  testWidgets('shows the copy-count pill when copyCount > 1', (tester) async {
    await tester.pumpWidget(host(const Book(title: 'Dune', copyCount: 4)));
    await tester.pump();
    expect(find.text('×4'), findsOneWidget);
  });

  testWidgets('a removed book shows Removed, not Not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Book(title: 'Old Tales', removed: true), unavailable: true),
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
        const Book(
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
