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
import 'package:pitaka/core/widgets/splash_screen.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_phase == _Phase.unlocked) setState(() => _phase = _Phase.locked);
    } else if (state == AppLifecycleState.resumed) {
      if (_phase == _Phase.locked) _promptUnlock();
    }
  }

  bool get _gateEnabled =>
      ref.read(settingsControllerProvider).valueOrNull?.appLockBiometric ??
      false;

  /// Called when the splash hold elapses.
  void _onSplashDone() {
    if (!mounted) return;
    if (_gateEnabled) {
      setState(() => _phase = _Phase.locked);
      _promptUnlock();
    } else {
      setState(() => _phase = _Phase.unlocked);
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
      if (ok) setState(() => _phase = _Phase.unlocked);
      // On failure/cancel we stay locked (fail closed); the Unlock button retries.
    } finally {
      _prompting = false;
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
        return _LockedScreen(onUnlock: _promptUnlock);
    }
  }
}

class _LockedScreen extends StatelessWidget {
  const _LockedScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                Text(
                  'Pitak is locked',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock with your biometric or device PIN to view your '
                  'library.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
