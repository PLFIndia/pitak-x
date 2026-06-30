/// App-lock suppression for intentional external activities (presentation).
///
/// Why this exists: the optional biometric app-lock (`AppGate`) re-locks
/// whenever the app is backgrounded (`paused`/`hidden`) so the library isn't
/// visible in the recents preview and so a thief can't resume into it. But
/// launching the system camera, the gallery picker, or the uCrop/image_cropper
/// activity ALSO sends our activity to `paused` — so returning from a cover
/// capture would wrongly demand a fingerprint mid-task.
///
/// The fix is a deliberate "lock suppression" flag, the same pattern Signal's
/// `ScreenLockController` uses: mark the one background→foreground cycle caused
/// by an action WE started as exempt, so the gate ignores it. A short grace
/// window after the action returns absorbs the lifecycle events that arrive
/// just after the external activity closes (the `resumed` can land a beat after
/// the awaited call completes).
///
/// Fail-CLOSED by design: suppression only ever covers a single in-flight
/// guarded action plus a brief grace period. It is NOT a global "disable the
/// lock" switch — any background event outside that window still locks.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'lock_suppressor.g.dart';

/// Holds whether the next background/foreground cycle should bypass the lock.
///
/// keepAlive: the flag must survive across the widget rebuilds that happen when
/// the app backgrounds for the external activity; an autoDispose provider could
/// be torn down at exactly the wrong moment.
@Riverpod(keepAlive: true)
class LockSuppressor extends _$LockSuppressor {
  Timer? _graceTimer;
  int _active = 0;

  /// Grace window kept open after a guarded action returns, to swallow the
  /// `resumed` (and any trailing `inactive`) that the OS delivers just after
  /// the external activity closes.
  static const Duration _grace = Duration(seconds: 2);

  @override
  bool build() {
    ref.onDispose(() => _graceTimer?.cancel());
    return false; // not suppressed by default (fail closed)
  }

  /// True while an external activity we launched is in flight, or within the
  /// grace window just after it returned. `AppGate` checks this before locking.
  bool get isSuppressed => state;

  /// Runs [action] (a call that launches an external activity: camera, picker,
  /// crop) with the app lock suppressed for that one background cycle. The flag
  /// is cleared a short grace period after [action] completes, success or
  /// throw. Re-entrant safe: nested/overlapping guards keep suppression on
  /// until the last one finishes.
  Future<T> guard<T>(Future<T> Function() action) async {
    _graceTimer?.cancel();
    _active++;
    state = true;
    try {
      return await action();
    } finally {
      _active--;
      if (_active <= 0) {
        _active = 0;
        // Keep suppression on through the grace window, then fail closed.
        _graceTimer?.cancel();
        _graceTimer = Timer(_grace, () {
          if (_active <= 0) state = false;
        });
      }
    }
  }

  /// Test/diagnostic hook: immediately clears suppression and any grace timer.
  @visibleForTesting
  void resetForTest() {
    _graceTimer?.cancel();
    _active = 0;
    state = false;
  }
}
