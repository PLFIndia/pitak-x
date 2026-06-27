import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/editable_text_field.dart';

void main() {
  Widget host({
    required String initial,
    required ValueChanged<String> onCommitted,
  }) => MaterialApp(
    home: Scaffold(
      body: EditableTextField(
        label: 'Library name',
        initial: initial,
        onCommitted: onCommitted,
      ),
    ),
  );

  testWidgets('starts in view mode showing the value + an Edit button', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: 'My Shelf', onCommitted: (_) {}));
    expect(find.text('My Shelf'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a blank value shows the greyed "Not set" placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: '', onCommitted: (_) {}));
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('tapping Edit reveals the field; check commits + collapses', (
    tester,
  ) async {
    String? committed;
    await tester.pumpWidget(
      host(initial: 'Old', onCommitted: (v) => committed = v),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'New Name');
    // The inline check (suffix icon) commits.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(committed, 'New Name');
    expect(find.byType(TextField), findsNothing); // collapsed back to view
    expect(find.text('New Name'), findsOneWidget);
  });

  testWidgets('commits the trimmed value', (tester) async {
    String? committed;
    await tester.pumpWidget(
      host(initial: '', onCommitted: (v) => committed = v),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  spaced  ');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(committed, 'spaced');
  });
}
