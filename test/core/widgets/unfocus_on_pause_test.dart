/// Tests for [UnfocusOnPause] (core/widgets).
///
/// Verifies the backgrounding fix for the stale-IME bug: a focused text field
/// must lose focus when the app is backgrounded (`hidden`/`paused`), so the
/// first tap after resume is a fresh focus gain that reopens the keyboard.
/// Also verifies `inactive` alone (transient system dialogs) does NOT drop
/// focus, and that a tap after resume re-focuses the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/unfocus_on_pause.dart';

void main() {
  Future<void> step(WidgetTester tester, AppLifecycleState s) async {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }

  Future<FocusNode> pumpFocusedField(WidgetTester tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnfocusOnPause(
          child: Scaffold(body: TextField(focusNode: focus)),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue, reason: 'field should focus on tap');
    return focus;
  }

  testWidgets('drops focus when the app is backgrounded', (tester) async {
    final focus = await pumpFocusedField(tester);

    // Valid OS order on background: inactive → hidden → paused.
    await step(tester, AppLifecycleState.inactive);
    await step(tester, AppLifecycleState.hidden);
    await step(tester, AppLifecycleState.paused);

    expect(focus.hasFocus, isFalse);

    // Restore foreground so later tests start clean (valid OS order:
    // paused → hidden → inactive → resumed; AppLifecycleListener asserts on
    // invalid transitions).
    await step(tester, AppLifecycleState.hidden);
    await step(tester, AppLifecycleState.inactive);
    await step(tester, AppLifecycleState.resumed);
  });

  testWidgets('keeps focus on a transient inactive (system dialog)', (
    tester,
  ) async {
    final focus = await pumpFocusedField(tester);

    await step(tester, AppLifecycleState.inactive);
    expect(focus.hasFocus, isTrue);

    await step(tester, AppLifecycleState.resumed);
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('tap after resume re-focuses the field', (tester) async {
    final focus = await pumpFocusedField(tester);

    await step(tester, AppLifecycleState.inactive);
    await step(tester, AppLifecycleState.hidden);
    await step(tester, AppLifecycleState.paused);
    expect(focus.hasFocus, isFalse);

    await step(tester, AppLifecycleState.hidden);
    await step(tester, AppLifecycleState.inactive);
    await step(tester, AppLifecycleState.resumed);

    // The user's tap is now a FRESH focus gain — this is the bug fix.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });
}
