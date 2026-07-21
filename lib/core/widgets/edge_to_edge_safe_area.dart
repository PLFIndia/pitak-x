/// App-wide system-inset guard for Android edge-to-edge (presentation util).
///
/// Since Android 15 (API 35) apps are drawn edge-to-edge by default: the app
/// renders BEHIND the system navigation bar (back/home/recents), and padding
/// content out of that zone is the app's job. Flutter's `ListView` only does
/// this automatically when no explicit `padding:` is passed — and nearly every
/// page in this app passes one, so bottom buttons ended up under the nav bar.
///
/// Fix (decision A): pad ONCE, globally, instead of at ~27 scrollable call
/// sites. This widget wraps the whole app subtree (via `MaterialApp.builder`)
/// in a [SafeArea] that consumes the bottom and side system insets:
///  - `top: false` — the status bar inset is left alone so each page's
///    [AppBar] keeps drawing its background behind the status bar as designed;
///  - bottom/left/right on — clears the nav bar in portrait AND the side
///    gesture/button insets in landscape.
///
/// The strip that the SafeArea vacates behind the nav bar is painted with the
/// theme's surface color (via [ColoredBox]) so it blends with page
/// backgrounds instead of showing through as black.
///
/// SafeArea removes the insets it consumed from the inherited [MediaQuery],
/// so the few pre-existing inner `SafeArea`s (app gate, splash, events,
/// drawer) become harmless no-ops — no double padding.
library;

import 'package:flutter/material.dart';

/// Wraps [child] so nothing renders under the system navigation bar.
///
/// Intended to be installed exactly once, in `MaterialApp.builder`, so every
/// current and future route (pages, dialogs, sheets) is covered.
class EdgeToEdgeSafeArea extends StatelessWidget {
  /// Creates the guard around [child].
  const EdgeToEdgeSafeArea({required this.child, super.key});

  /// The app subtree (the navigator) to keep clear of system bars.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Paint the vacated nav-bar strip in the page background color so it
      // reads as part of the page, not a black band.
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false, // AppBars handle the status bar themselves.
        child: child,
      ),
    );
  }
}
