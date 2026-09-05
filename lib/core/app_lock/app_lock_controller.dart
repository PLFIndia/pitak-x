/// App-lock state machine (application-layer logic for the launch gate).
///
/// Owns the phase the optional biometric app lock is in — `splash`, `locked`
/// or `unlocked` — and every transition between them. It is a plain Riverpod
/// `Notifier` (no widget code) so the fail-closed rules can be unit-tested
/// with a `ProviderContainer`, and so the two widgets that need the phase
/// (`AppLockObserver` feeding lifecycle/back events in, `AppGate` painting the
/// cover) share one source of truth instead of each keeping their own flag.
///
/// Before B01 (astra-review.md) this logic lived inside `AppGate`'s widget
/// state, and the gate was only the `home` route: any pushed screen or dialog
/// stayed on top of the lock. Moving the state here lets the cover live above
/// the whole navigator (see `AppGate`).
///
/// FAIL-CLOSED throughout:
///  - unknown / still-loading / errored settings → treated as lock ENABLED;
///  - a cancelled or failed prompt keeps the app locked;
///  - only one prompt is ever in flight;
///  - "turn off app lock" (recovery for a device with no screen lock) opens the
///    app only after the setting is confirmed persisted.
///
/// Prompt/recovery semantics are unchanged from the previous `AppGate`
/// (decisions Q2=B re-gate on resume, Q5 recovery only when the device has no
/// credential at all).
library;

import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart' show immutable;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lock_controller.g.dart';

/// Phases of the launch gate.
enum AppLockPhase {
  /// Initial branding splash (cold start). The app content is not shown.
  splash,

  /// Gate enabled and waiting for / retrying a biometric prompt.
  locked,

  /// Authenticated (or gate disabled) — app content is shown.
  unlocked,
}

/// Immutable view of the lock: the [phase] plus whether the last failed prompt
/// was traced to "the device has no screen lock at all" ([noCredential]),
/// which is the only state where the locked screen offers to turn the lock off.
@immutable
final class AppLockState {
  /// Creates a lock state.
  const AppLockState({required this.phase, this.noCredential = false});

  /// Current phase of the gate.
  final AppLockPhase phase;

  /// True once a failed prompt was traced to "no device credential".
  final bool noCredential;

  /// Whether the app content may be shown and interacted with.
  bool get isUnlocked => phase == AppLockPhase.unlocked;

  /// Copy with changed fields.
  AppLockState copyWith({AppLockPhase? phase, bool? noCredential}) =>
      AppLockState(
        phase: phase ?? this.phase,
        noCredential: noCredential ?? this.noCredential,
      );

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.phase == phase &&
      other.noCredential == noCredential;

  @override
  int get hashCode => Object.hash(phase, noCredential);

  @override
  String toString() =>
      'AppLockState(phase: $phase, noCredential: $noCredential)';
}

/// Drives the app-lock phase. `keepAlive`: the lock must outlive any widget
/// rebuild — it is the thing protecting the screen while the app is paused.
@Riverpod(keepAlive: true)
class AppLockController extends _$AppLockController {
  bool _prompting = false;

  @override
  AppLockState build() => const AppLockState(phase: AppLockPhase.splash);

  /// Called by the splash once its hold elapses.
  ///
  /// FAIL-CLOSED: AWAITS the settings load rather than reading a possibly-null
  /// transient value (a `valueOrNull` read here once defaulted to "disabled"
  /// while settings were still loading, briefly showing the library). Any load
  /// failure is treated as ENABLED (locked), never open.
  Future<void> onSplashDone() async {
    if (state.phase != AppLockPhase.splash) return; // idempotent
    final enabled = await _resolveGateEnabled();
    if (enabled) {
      state = state.copyWith(phase: AppLockPhase.locked);
      await unlock();
    } else {
      state = state.copyWith(phase: AppLockPhase.unlocked);
    }
  }

  /// Feeds an OS lifecycle change in (from `AppLockObserver`).
  ///
  /// Q2=B: re-gate on every resume from background. We lock on `paused` /
  /// `hidden` so the app content is not visible in the recents preview, and
  /// re-prompt on `resumed`. Transient `inactive` (a system dialog) is ignored.
  /// A background cycle WE caused (camera / gallery / crop, marked via
  /// [LockSuppressor]) is exempt so a cover capture doesn't demand a
  /// fingerprint mid-task.
  void onAppLifecycleState(AppLifecycleState lifecycle) {
    if (state.phase == AppLockPhase.splash) return; // still booting
    if (!_gateEnabled) return;
    if (ref.read(lockSuppressorProvider.notifier).isSuppressed) return;
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      if (state.phase == AppLockPhase.unlocked) {
        state = state.copyWith(phase: AppLockPhase.locked);
      }
    } else if (lifecycle == AppLifecycleState.resumed) {
      if (state.phase == AppLockPhase.locked) unlock();
    }
  }

  /// Whether the lock gate is enabled, for runtime (post-splash) decisions.
  /// FAIL-CLOSED: an unknown (still-loading / errored) settings state is
  /// treated as ENABLED, never open.
  bool get _gateEnabled =>
      ref.read(settingsControllerProvider).valueOrNull?.appLockBiometric ??
      true;

  Future<bool> _resolveGateEnabled() async {
    try {
      final settings = await ref.read(settingsControllerProvider.future);
      return settings.appLockBiometric;
    } on Object {
      return true; // fail closed
    }
  }

  /// Runs the biometric/device-credential prompt. Success → unlocked. Failure
  /// or cancel → stays locked; then finds out WHY, and only when the device
  /// has no credential at all flags [AppLockState.noCredential] so the locked
  /// screen can offer the recovery path.
  Future<void> unlock() async {
    if (state.phase != AppLockPhase.locked) return;
    if (_prompting) return; // never stack system prompts
    _prompting = true;
    try {
      final auth = ref.read(biometricAuthenticatorProvider);
      final ok = await auth.authenticate(
        reason: 'Unlock Pitak to view your library',
      );
      // The app may have been backgrounded again while the prompt was up;
      // only an accepted prompt while still in `locked` opens the gate.
      if (ok && state.phase == AppLockPhase.locked) {
        state = const AppLockState(phase: AppLockPhase.unlocked);
        return;
      }
      if (ok) return;
      final status = await auth.deviceCredentialStatus();
      state = state.copyWith(
        noCredential: status == DeviceCredentialStatus.noneConfigured,
      );
    } finally {
      _prompting = false;
    }
  }

  /// Recovery: the user has no screen lock, so no prompt can ever pass. Turn
  /// the app lock OFF (persisted) and open the app. Fail closed if the setting
  /// cannot be saved: stay locked and keep the button.
  Future<void> disableAppLock() async {
    if (state.phase != AppLockPhase.locked) return;
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setAppLockBiometric(enabled: false);
    } on Object {
      return; // setting not persisted → remain locked
    }
    final saved = ref.read(settingsControllerProvider).valueOrNull;
    if (saved != null && !saved.appLockBiometric) {
      state = const AppLockState(phase: AppLockPhase.unlocked);
    }
  }
}
