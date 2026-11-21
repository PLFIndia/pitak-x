/// Questions a widget test can ask about how a text was laid out.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the ONE text that [finder] finds stands on a single line.
///
/// Why the bound is one and a half lines, not two (beginner note, found on
/// 2026-11-20): the height of a caret is a hair MORE than the height of a
/// line (40.04 against 40.0 at twice the text size). "Lower than two
/// carets" is therefore also true for a text that stands on exactly two
/// lines, and a check written that way can never fail.
///
/// What this can and cannot say: a widget test draws text in the test
/// font, in which every letter is a square as wide as the font is high.
/// Real letters are about half as wide. So "one line here" means one line
/// on a phone too, but "two lines here" does not mean two lines on a phone.
bool standsOnOneLine(WidgetTester tester, Finder finder) {
  final text = tester.renderObject<RenderParagraph>(finder);
  final oneLine = text.getFullHeightForCaret(const TextPosition(offset: 0));
  return text.size.height < 1.5 * oneLine;
}

/// Whether what [finder] finds lies inside the screen from left to right:
/// nothing of it is pushed off the edge.
bool liesWithinScreenWidth(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return rect.left >= 0 && rect.right <= width;
}
