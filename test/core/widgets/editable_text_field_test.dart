import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/editable_text_field.dart';

/// A host whose `initial` can be changed from the outside (what the Settings
/// page does when the controller publishes an adopted identity).
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.onCommitted});

  final String initial;
  final Future<bool> Function(String) onCommitted;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String initial = widget.initial;

  void external(String next) => setState(() => initial = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: EditableTextField(
        label: 'Library name',
        initial: initial,
        onCommitted: widget.onCommitted,
      ),
    ),
  );
}

void main() {
  Future<bool> accept(String _) async => true;

  Widget host({
    required String initial,
    required Future<bool> Function(String) onCommitted,
  }) => _Host(initial: initial, onCommitted: onCommitted);

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  }

  testWidgets('starts in view mode showing the value + an Edit button', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: 'My Shelf', onCommitted: accept));
    expect(find.text('My Shelf'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a blank value shows the greyed "Not set" placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: '', onCommitted: accept));
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('a successful write commits + collapses', (tester) async {
    String? committed;
    await tester.pumpWidget(
      host(
        initial: 'Old',
        onCommitted: (v) async {
          committed = v;
          return true;
        },
      ),
    );
    await openEditor(tester);

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
      host(
        initial: '',
        onCommitted: (v) async {
          committed = v;
          return true;
        },
      ),
    );
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), '  spaced  ');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(committed, 'spaced');
  });

  testWidgets('item 14: a failed write stays editing with the input intact '
      'and never shows it as the saved value', (tester) async {
    await tester.pumpWidget(
      host(initial: 'Old', onCommitted: (_) async => false),
    );
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget, reason: 'still editing');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Unsaved',
    );
    expect(find.text('Edit'), findsNothing);
    // The check is back so the user can retry.
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Backing out of the editor afterwards must NOT reveal "Unsaved" as the
    // committed value: a later successful save of a different text wins.
    await tester.enterText(find.byType(TextField), 'Unsaved');
    await tester.pumpWidget(
      host(initial: 'Old', onCommitted: (_) async => true),
    );
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget); // now really saved
  });

  testWidgets('item 14: an external change updates a non-editing field', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: 'Mine', onCommitted: accept));
    expect(find.text('Mine'), findsOneWidget);

    tester.state<_HostState>(find.byType(_Host)).external('Theirs');
    await tester.pumpAndSettle();

    expect(find.text('Theirs'), findsOneWidget);
    expect(find.text('Mine'), findsNothing);
    // Opening the editor starts from the new value, not the stale one.
    await openEditor(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Theirs',
    );
  });

  testWidgets('item 14: an external change during editing does not clobber '
      'the input', (tester) async {
    await tester.pumpWidget(host(initial: 'Mine', onCommitted: accept));
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Typing');

    tester.state<_HostState>(find.byType(_Host)).external('Theirs');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Typing',
    );
  });

  testWidgets('item 14: a duplicate submit while saving is ignored', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      host(
        initial: 'Old',
        onCommitted: (_) {
          calls++;
          return gate.future;
        },
      ),
    );
    await openEditor(tester);
    await tester.enterText(find.byType(TextField), 'New');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Saving: the check is replaced by a spinner, text still readable.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    // A second "done" while in flight does not start a second save.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, 1);

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('New'), findsOneWidget);
  });
}
