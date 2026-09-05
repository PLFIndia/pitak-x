/// Feeds OS lifecycle + Android back events into [AppLockController].
///
/// This widget sits ABOVE `MaterialApp` in the tree (see `main.dart`). Why
/// there and not inside a route:
///
///  1. **Lifecycle:** the lock must react to `paused`/`resumed` no matter which
///     route or dialog is open — a route-level observer is never guaranteed
///     to be alive.
///  2. **Back button:** `WidgetsBinding.handlePopRoute` asks observers in
///     registration order. `WidgetsApp` (inside `MaterialApp`) registers in
///     its own `initState` and pops the navigator. A widget created ABOVE it
///     registers FIRST, so while the app is locked we can consume the back
///     press before the navigator would pop a route hidden under the cover
///     (a hidden dialog's cancel callback running blind). Decision (B01,
///     Session 2, option a): back while locked LEAVES THE APP via
///     `SystemNavigator.pop()`, like Signal/Bitwarden lock screens do; the
///     route stack is kept for the next unlock.
///
/// Placement pattern (lock cover owned by the root, not by a route) follows
/// how Bitwarden mobile and Signal-Android gate their windows — from memory,
/// unverified; nothing is copied.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/app_lock/app_lock_controller.dart';

/// Wraps [child] (the `MaterialApp`) and forwards lifecycle/back events to
/// the app-lock controller. Renders [child] unchanged.
class AppLockObserver extends ConsumerStatefulWidget {
  /// Creates the observer around [child].
  const AppLockObserver({required this.child, super.key});

  /// The app subtree (normally the `MaterialApp`).
  final Widget child;

  @override
  ConsumerState<AppLockObserver> createState() => _AppLockObserverState();
}

class _AppLockObserverState extends ConsumerState<AppLockObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Registered here, in the parent's initState — i.e. BEFORE the
    // MaterialApp child's initState runs — so didPopRoute gets first say.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLockControllerProvider.notifier).onAppLifecycleState(state);
  }

  @override
  Future<bool> didPopRoute() async {
    if (ref.read(appLockControllerProvider).isUnlocked) {
      return false; // let MaterialApp's navigator handle it normally
    }
    // Locked or still on the splash: never pop the hidden route stack.
    // Leave the app instead (option a). Errors from the platform call are
    // reported by the framework's own handler, not swallowed here.
    await SystemNavigator.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
