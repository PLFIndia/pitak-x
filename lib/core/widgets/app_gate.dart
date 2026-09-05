/// App launch gate (presentation, AGENTS.md §3.1).
///
/// Covers the WHOLE app — every route, dialog, bottom sheet — with:
///  1. a ~1s branding [SplashScreen] on cold start;
///  2. an OPT-IN biometric lock screen (Settings → Security; default OFF) that
///     must pass before the app is shown, re-evaluated on every resume from
///     background (decision Q2=B).
///
/// WHERE IT LIVES (B01, astra-review.md): this widget is installed in
/// `MaterialApp.builder`, which wraps the app's `Navigator` itself. Before the
/// fix it was the `home` route, so anything pushed on top (details, vault,
/// settings, dialogs) stayed visible and interactive after a rejected prompt.
/// Now the navigator is the gate's `child` and the cover is painted above it.
///
/// HOW IT COVERS: `Visibility(maintainState: true)` around the navigator.
/// That is `ExcludeFocus` + `TickerMode(off)` + `Offstage`: the route stack is
/// kept alive (a good unlock resumes exactly where the user was — decision
/// Session 2), but while locked nothing under the cover is painted, hit-tested,
/// focusable, or exposed to accessibility. The lock screen is the only thing
/// on screen — including in the recents preview.
///
/// The phase itself (`splash / locked / unlocked`) and all fail-closed rules
/// live in [AppLockController]; this widget only renders it. Lifecycle and
/// back-button input come from `AppLockObserver` above `MaterialApp`.
///
/// RECOVERY (review 2026-09-03, decision Q5): if the DEVICE can no longer
/// authenticate anyone — the user removed their screen lock — every prompt
/// fails and the gate would lock the user out of their own
/// (unencrypted-by-this-gate) library forever. In that one state the locked
/// screen explains why and offers to turn the app lock off. It is a deliberate,
/// visible action, not a silent fail-open, and only offered when
/// authentication is impossible, never after a mere cancel or a wrong
/// fingerprint.
///
/// HONESTY: this is a UI gate, not at-rest encryption. It deters casual access
/// on an unlocked, foregrounded device; the encrypted vault remains the secure
/// store for sensitive data. The locked-screen copy says as much.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/app_lock/app_lock_controller.dart';
import 'package:pitaka/core/widgets/splash_screen.dart';

/// Paints the splash / lock screen above [child] (the app's navigator) until
/// the app lock is satisfied.
class AppGate extends ConsumerWidget {
  /// Creates the gate around [child].
  const AppGate({required this.child, super.key});

  /// The app content (normally the `Navigator` handed to
  /// `MaterialApp.builder`).
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider);
    // `.notifier` is watched (not read) in build, matching LibraryPage: the
    // controller is keepAlive so this never rebuilds on its own.
    final controller = ref.watch(appLockControllerProvider.notifier);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The real app. Kept alive but fully inert while covered (see
        // library doc: Offstage + ExcludeFocus + TickerMode off).
        Visibility(visible: lock.isUnlocked, maintainState: true, child: child),
        switch (lock.phase) {
          AppLockPhase.unlocked => const SizedBox.shrink(),
          AppLockPhase.splash => SplashScreen(onDone: controller.onSplashDone),
          AppLockPhase.locked => _LockedScreen(
            onUnlock: controller.unlock,
            onDisableLock: lock.noCredential ? controller.disableAppLock : null,
          ),
        },
      ],
    );
  }
}

class _LockedScreen extends StatelessWidget {
  const _LockedScreen({required this.onUnlock, this.onDisableLock});

  final VoidCallback onUnlock;

  /// Non-null only when the device cannot authenticate anyone (no screen
  /// lock configured) — the one state where "turn off app lock" is offered.
  final VoidCallback? onDisableLock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final noCredential = onDisableLock != null;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: scheme.primary),
                const SizedBox(height: 24),
                Text('Pitak is locked', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  noCredential
                      ? 'This phone has no screen lock (no fingerprint, PIN '
                            'or pattern), so there is nothing to unlock Pitak '
                            'with. Set up a screen lock in your phone\u2019s '
                            'settings and try again — or turn off the app '
                            'lock. (The app lock only hides the screen; your '
                            'borrowers vault stays encrypted either way.)'
                      : 'Unlock with your biometric or device PIN to view your '
                            'library.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
                if (noCredential) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onDisableLock,
                    child: const Text('Turn off app lock'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
