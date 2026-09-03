/// App launch gate (presentation, AGENTS.md §3.1).
///
/// Wraps the Library home with:
///  1. a ~1s branding [SplashScreen] on cold start;
///  2. an OPT-IN biometric gate (Settings → Security; default OFF) that must
///     pass before the library is shown, re-evaluated on every resume from
///     background (decision Q2=B).
///
/// FAIL-CLOSED: while the gate is enabled and not yet satisfied, the library is
/// never rendered — a locked screen with a Retry/Unlock button is shown
/// instead. A cancelled or failed prompt keeps the app locked.
///
/// RECOVERY (review 2026-09-03, decision Q5): if the DEVICE can no longer
/// authenticate anyone — the user removed their screen lock, so there is no
/// biometric and no PIN to check — every prompt fails and the gate would lock
/// the user out of their own (unencrypted-by-this-gate) library forever. In
/// that one state the locked screen explains why and offers to turn the app
/// lock off. It is a deliberate, visible action, not a silent fail-open, and
/// it is only offered when authentication is impossible, never after a mere
/// cancel or a wrong fingerprint.
///
/// HONESTY: this is a UI gate, not at-rest encryption. It deters casual access
/// on an unlocked, foregrounded device; the encrypted vault remains the secure
/// store for sensitive data. The locked-screen copy says as much.
///
/// The biometric prompt itself reuses the existing #34 biometric authenticator
/// (a pure capability gate); `biometricOnly:false` lets the device PIN/pattern
/// act as a fallback (decision Q5=A).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/core/widgets/splash_screen.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

/// Phases of the launch gate.
enum _Phase {
  /// Initial branding splash (cold start).
  splash,

  /// Gate enabled and waiting for / retrying a biometric prompt.
  locked,

  /// Authenticated (or gate disabled) — library is shown.
  unlocked,
}

/// Gates the [LibraryPage] behind the splash + optional biometric lock.
class AppGate extends ConsumerStatefulWidget {
  /// Creates the gate.
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  _Phase _phase = _Phase.splash;
  bool _prompting = false;

  /// True once a failed prompt was traced to "the device has no screen lock";
  /// drives the recovery copy + button on the locked screen.
  bool _noCredential = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Q2=B: re-gate on every resume from background. Only re-lock if the gate
    // is enabled; ignore transient inactive states (don't lock on a system
    // dialog). We lock on `paused` so the library isn't visible in the recents
    // preview, and re-prompt on `resumed`.
    if (!_gateEnabled) return;
    // Don't re-lock for a background cycle WE caused (camera / gallery picker /
    // image crop). Those launch a separate OS activity that pauses us; the
    // LockSuppressor marks that one cycle exempt so a cover capture doesn't
    // demand a fingerprint mid-task. Any other background still locks.
    if (ref.read(lockSuppressorProvider.notifier).isSuppressed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_phase == _Phase.unlocked) setState(() => _phase = _Phase.locked);
    } else if (state == AppLifecycleState.resumed) {
      if (_phase == _Phase.locked) _promptUnlock();
    }
  }

  /// Whether the lock gate is enabled, for runtime (post-splash) lifecycle
  /// decisions. FAIL-CLOSED: an unknown (still-loading / errored) settings
  /// state is treated as ENABLED, never open — so we never leave the library
  /// visible in recents on a state we can't prove is unlocked. In steady-state
  /// running, settings are resolved and this returns the real value.
  bool get _gateEnabled =>
      ref.read(settingsControllerProvider).valueOrNull?.appLockBiometric ??
      true;

  /// Called when the splash hold elapses.
  ///
  /// FAIL-CLOSED (M2): we AWAIT the settings load rather than reading a
  /// possibly-null transient value. Reading `valueOrNull` here used to default
  /// to "gate disabled" while settings were still loading after the ~1s splash,
  /// rendering the library unlocked in a race. Awaiting the future removes the
  /// race; any load failure is treated as ENABLED (locked), never open.
  Future<void> _onSplashDone() async {
    if (!mounted) return;
    final enabled = await _resolveGateEnabled();
    if (!mounted) return;
    if (enabled) {
      setState(() => _phase = _Phase.locked);
      await _promptUnlock();
    } else {
      setState(() => _phase = _Phase.unlocked);
    }
  }

  /// Resolves the gate-enabled flag by awaiting the settings load. Fail-closed:
  /// any error resolves to `true` (locked), so a broken settings load can never
  /// open the gate.
  Future<bool> _resolveGateEnabled() async {
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      return settings.appLockBiometric;
    } on Object {
      return true; // fail closed
    }
  }

  Future<void> _promptUnlock() async {
    if (_prompting) return; // never stack system prompts
    _prompting = true;
    try {
      final auth = ref.read(biometricAuthenticatorProvider);
      final ok = await auth.authenticate(
        reason: 'Unlock Pitak to view your library',
      );
      if (!mounted) return;
      if (ok) {
        setState(() {
          _phase = _Phase.unlocked;
          _noCredential = false;
        });
        return;
      }
      // On failure/cancel we stay locked (fail closed); the Unlock button
      // retries. Then find out WHY it failed: only when the device has no
      // credential at all do we offer the recovery path (see class doc).
      final status = await auth.deviceCredentialStatus();
      if (!mounted) return;
      setState(
        () => _noCredential = status == DeviceCredentialStatus.noneConfigured,
      );
    } finally {
      _prompting = false;
    }
  }

  /// Recovery: the user has no screen lock, so no prompt can ever pass. Turn
  /// the app lock OFF (persisted) and open the library. Fail closed if the
  /// setting cannot be saved: stay locked and keep the button.
  Future<void> _disableAppLock() async {
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setAppLockBiometric(enabled: false);
    } on Object {
      return; // setting not persisted → remain locked
    }
    if (!mounted) return;
    final saved = ref.read(settingsControllerProvider).valueOrNull;
    if (saved != null && !saved.appLockBiometric) {
      setState(() {
        _phase = _Phase.unlocked;
        _noCredential = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.splash:
        return SplashScreen(onDone: _onSplashDone);
      case _Phase.unlocked:
        return const LibraryPage();
      case _Phase.locked:
        return _LockedScreen(
          onUnlock: _promptUnlock,
          onDisableLock: _noCredential ? _disableAppLock : null,
        );
    }
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
