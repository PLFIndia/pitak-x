/// A home page with a form opened ABOVE it, and the system's Back, for the
/// tests of what a form does when the user leaves it (review finding P4-M1).
///
/// Why a home page (beginner note): most page tests make their page the
/// first and only page of the app. Such a page cannot be left by Back, so a
/// test of "Back leaves the form" or "Back asks first" would prove nothing.
/// Here the form is pushed the way the app pushes it, as a
/// `MaterialPageRoute`, and "the form is gone" means: the home page shows
/// again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The label of the home page's one button. A test that finds it on the
/// screen knows the form above it is gone.
const String formBackHomeLabel = 'home page: open the form';

/// Finds the home page while it is the page on the screen.
Finder findFormBackHome() => find.text(formBackHomeLabel);

/// Finds the title of the question a form asks before unsaved input is
/// lost. Written out here, not taken from the app's code: a changed word
/// has to fail the tests (decision D96 of PLAN.md).
Finder findDiscardQuestion() => find.text('Discard changes?');

/// Finds the question's button that stays on the form.
Finder findKeepEditing() => find.text('Keep editing');

/// Finds the question's button that leaves the form.
Finder findDiscard() => find.text('Discard');

/// Pumps a home page and opens [page] above it.
///
/// [overrides] are the Riverpod overrides the page needs. [theme] is the
/// app theme to draw with (the tests of contrast pass the app's own light
/// and dark themes). With [settle] false the helper pumps single frames
/// instead of waiting for every animation to end: a page that shows a
/// spinner from its first frame never "settles".
Future<void> pumpFormAboveHome(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
  ThemeData? theme,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text(formBackHomeLabel),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(findFormBackHome());
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // One frame to start the page transition, one to end it.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Presses the system's Back (the gesture from the screen's edge, or the
/// Back button of three-button navigation), as Android hands it to Flutter.
///
/// With [settle] false it pumps single frames; see [pumpFormAboveHome].
Future<void> pressSystemBack(WidgetTester tester, {bool settle = true}) async {
  await tester.binding.handlePopRoute();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}
