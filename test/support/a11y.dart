import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours (1.0 – 21.0), the
/// same formula [textContrastGuideline] applies to rendered pixels. Used by
/// the colour-pair tests that pin a shade against the real card/surface
/// colour of `AppTheme` instead of assuming white.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Runs only [textContrastGuideline] against the pumped tree: for widget
/// fragments (a lone card) that have no page-level tap targets to label.
Future<void> expectMeetsTextContrast(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  } finally {
    handle.dispose();
  }
}

/// Runs Flutter's three built-in accessibility guideline checks against the
/// currently-pumped widget tree (the accessibility gate every page test runs):
///
///  * [androidTapTargetGuideline] — tappable nodes are at least 48×48 dp;
///  * [labeledTapTargetGuideline] — tappable nodes have a semantic label;
///  * [textContrastGuideline] — text meets minimum contrast.
///
/// One helper, not 16 copies: every `*_page_test.dart` suite calls this from
/// its own 'meets accessibility guidelines' test after pumping its page.
/// `ensureSemantics()` builds the semantics tree the matchers inspect; the
/// handle is always disposed.
Future<void> expectMeetsA11yGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  } finally {
    handle.dispose();
  }
}
