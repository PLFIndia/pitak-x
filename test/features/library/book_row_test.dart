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
}
