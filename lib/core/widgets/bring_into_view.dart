/// Brings what a page has just said into view (core/widgets; decision
/// D177).
///
/// WHY THIS EXISTS (beginner note): some pages are longer than the screen,
/// and say what came of a tap UNDER the button that was tapped. On a small
/// screen, or with a large font, that sentence can lie below the screen:
/// the user taps, and as far as they can see nothing happens. After a save
/// the system's own window has closed by then, so the page is all the user
/// has. A page that calls this after it has set its result scrolls just far
/// enough for the result to be read.
///
/// The page gives two keys: one for the whole result (a sentence and
/// whatever notes stand under it) and one for its first line. The END of
/// the result is brought onto the screen; when the result is taller than
/// the screen, its first line wins, because that is where reading starts.
///
/// One thing the page has to see to itself: a list builds only what is
/// near the screen, and what is not built cannot be scrolled to. So the
/// result has to be part of the same list item as the button that leads to
/// it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// How long the scroll takes, unless the phone is set to show no
/// animations.
const Duration _scrollDuration = Duration(milliseconds: 200);

/// After the frame that is about to be drawn, scrolls the list around
/// [result] just far enough that its end is on the screen, and then makes
/// sure that [firstLine] has not left the screen at the top.
///
/// Call it right after the `setState` (or the state change) that makes the
/// result appear. Does nothing when the result is not on the page any more
/// by then, and nothing when it is in view already.
void bringResultIntoView({
  required GlobalKey result,
  required GlobalKey firstLine,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_bring(result, firstLine));
  });
}

Future<void> _bring(GlobalKey result, GlobalKey firstLine) async {
  final resultContext = result.currentContext;
  if (resultContext == null || !resultContext.mounted) return;
  // A phone set to "remove animations" gets the jump without one.
  final duration = MediaQuery.disableAnimationsOf(resultContext)
      ? Duration.zero
      : _scrollDuration;
  await Scrollable.ensureVisible(
    resultContext,
    duration: duration,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  // Read again: the page may have changed while the list was moving.
  final firstContext = firstLine.currentContext;
  if (firstContext == null || !firstContext.mounted) return;
  await Scrollable.ensureVisible(
    firstContext,
    duration: duration,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
  );
}
