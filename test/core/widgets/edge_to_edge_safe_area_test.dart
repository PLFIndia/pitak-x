/// Tests for [EdgeToEdgeSafeArea] (core/widgets).
///
/// Simulates an Android edge-to-edge navigation-bar inset via
/// [FakeViewPadding] and verifies that content installed through
/// `MaterialApp.builder` — the way `main.dart` wires it — is padded clear of
/// the system bars, that the status bar (top) inset is left for AppBars, and
/// that pre-existing inner [SafeArea]s do not double-pad.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/edge_to_edge_safe_area.dart';

void main() {
  const navBarInset = 48.0; // typical 3-button nav bar height (logical px)

  /// Pumps [home] inside a MaterialApp wired exactly like main.dart, with a
  /// fake bottom system inset.
  Future<void> pumpWithInset(WidgetTester tester, Widget home) async {
    tester.view.padding = const FakeViewPadding(bottom: navBarInset * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBarInset * 3);
    // FakeViewPadding is in physical px; devicePixelRatio is 3.0 in tests,
    // so bottom: 144 physical = 48 logical.
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            EdgeToEdgeSafeArea(child: child ?? const SizedBox.shrink()),
        home: home,
      ),
    );
  }

  testWidgets('bottom-aligned button is padded above the nav bar inset', (
    tester,
  ) async {
    await pumpWithInset(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: FilledButton(onPressed: () {}, child: const Text('Save')),
        ),
      ),
    );

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonBottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
    // The button must rest ON or ABOVE the nav bar's top edge, never under it.
    expect(buttonBottom, lessThanOrEqualTo(screenHeight - navBarInset));
  });

  testWidgets('top inset is left alone for AppBars', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            EdgeToEdgeSafeArea(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          appBar: AppBar(title: const Text('Title')),
          body: const SizedBox.expand(),
        ),
      ),
    );

    // The AppBar must still draw from y=0 (behind the status bar): the
    // wrapper's `top: false` leaves the status-bar inset to the AppBar.
    expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
  });

  testWidgets('inner SafeArea does not double-pad', (tester) async {
    // Mirrors pages that already had their own SafeArea (events, app gate):
    // the outer wrapper consumes the inset from MediaQuery, so the inner one
    // must add nothing.
    await pumpWithInset(
      tester,
      Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FilledButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      ),
    );

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonBottom = tester.getBottomLeft(find.byType(FilledButton)).dy;
    // Exactly one inset's worth of padding — flush against the safe edge.
    expect(buttonBottom, screenHeight - navBarInset);
  });
}
