import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/presentation/widgets/book_row.dart';

void main() {
  Widget host(Book book, {bool unavailable = false}) => MaterialApp(
    home: Scaffold(
      body: BookRow(book: book, unavailable: unavailable, onTap: () {}),
    ),
  );

  testWidgets('shows the "Not available" badge when unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Book(title: 'Hobbit'), unavailable: true),
    );
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('no availability badge when available', (tester) async {
    await tester.pumpWidget(host(const Book(title: 'Hobbit')));
    expect(find.text('Not available'), findsNothing);
  });

  testWidgets('a removed book shows Removed, not Not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Book(title: 'Hobbit', removed: true), unavailable: true),
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
        const Book(
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
}
