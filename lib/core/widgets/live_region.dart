/// A part of the screen that a screen reader reads out by itself when it
/// appears (shared presentation helper).
///
/// WHY THIS FILE EXISTS (beginner note): a page that says "Backup saved as
/// NAME." under its button has told a user who SEES the screen. A user of a
/// screen reader (TalkBack, VoiceOver) hears only what is under the finger,
/// so a new sentence somewhere else on the page goes unheard. The platforms
/// have a name for the cure: a "live region", a part of the screen whose
/// new words are read out politely, after what is being said just now.
///
/// TWO things are needed, and this widget is their one place (decision
/// D190):
///
///  * the flag `liveRegion`, which says "read this out";
///  * a node OF ITS OWN (`container`). Without it the flag goes up into the
///    node around it. In a list that is the whole list item, and then
///    everything else in that item (a note, a progress line that changes at
///    every step) would be read out with it, again and again.
library;

import 'package:flutter/widgets.dart';

/// Wraps [child] so that a screen reader reads its words out when it
/// appears. Use it for the RESULT of something the user started, and only
/// while there is one: a region that is built anew is read anew.
class LiveRegion extends StatelessWidget {
  /// Creates the region around [child].
  const LiveRegion({required this.child, super.key});

  /// What is read out: every text inside, in its order, as one.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(container: true, liveRegion: true, child: child);
  }
}
