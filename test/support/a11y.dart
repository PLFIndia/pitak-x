import 'package:flutter_test/flutter_test.dart';

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
