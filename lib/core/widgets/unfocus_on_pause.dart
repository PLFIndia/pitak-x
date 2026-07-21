/// Releases keyboard focus when the app is backgrounded (presentation util).
///
/// Why this exists: when Android backgrounds the app mid-typing, the OS closes
/// the keyboard but Flutter's [FocusManager] still believes the text field has
/// primary focus. On resume, tapping that same field is a no-op focus-wise
/// (it already "has" focus), so on many devices/OEM keyboards the IME
/// connection is never re-established — the cursor and keyboard don't come
/// back until the user taps a *different* field.
///
/// The fix is the standard one: explicitly unfocus on `paused`/`hidden`, so
/// the first tap after resume is a fresh focus gain that reliably reopens the
/// keyboard. This also satisfies AGENTS.md §6.6 (clear sensitive field state
/// on backgrounding) for the passphrase fields.
///
/// `inactive` is deliberately ignored — it fires for transient interruptions
/// (permission dialogs, biometric prompts, notification shade) where yanking
/// focus would be wrong.
///
/// Unfocusing goes through the [FocusManager] primary focus, so it works
/// no matter where focus lives (home page, pushed route, or dialog) even
/// though this widget only wraps the home subtree.
library;

import 'package:flutter/widgets.dart';

/// Wraps [child] and drops primary focus whenever the app leaves the
/// foreground (`hidden`/`paused`).
class UnfocusOnPause extends StatefulWidget {
  /// Creates the wrapper around [child].
  const UnfocusOnPause({required this.child, super.key});

  /// The subtree to render; unaffected except for focus release on pause.
  final Widget child;

  @override
  State<UnfocusOnPause> createState() => _UnfocusOnPauseState();
}

class _UnfocusOnPauseState extends State<UnfocusOnPause> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    // AppLifecycleListener manages its own WidgetsBinding observer
    // registration; we only need to dispose it.
    _listener = AppLifecycleListener(onStateChange: _onStateChange);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onStateChange(AppLifecycleState state) {
    // `hidden` always precedes `paused`, but handling both is harmless
    // (unfocus is idempotent) and mirrors AppGate's re-lock condition.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
