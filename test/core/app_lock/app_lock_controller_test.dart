/// Unit tests for [AppLockController]: every phase transition and every
/// fail-closed rule, driven through a bare [ProviderContainer] (no widgets).
library;

import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/app_lock/app_lock_controller.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scriptable prompt. [gate], when set, holds the prompt open until completed
/// so a test can interleave lifecycle events with an in-flight prompt.
class _FakeAuth implements BiometricAuthenticator {
  _FakeAuth({required this.result});
  bool result;
  int prompts = 0;
  Completer<void>? gate;
  DeviceCredentialStatus credentialStatus = DeviceCredentialStatus.available;

  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;

  @override
  Future<DeviceCredentialStatus> deviceCredentialStatus() async =>
      credentialStatus;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    if (gate != null) await gate!.future;
    return result;
  }
}

/// Settings repo whose [load] can be delayed or made to throw; writes of the
/// app-lock flag either succeed (recorded) or throw.
class _ScriptedSettingsRepo implements SettingsRepository {
  _ScriptedSettingsRepo({
    required this.settings,
    this.loadGate,
    this.loadThrows = false,
    this.writeThrows = false,
  });
  final AppSettings settings;
  final Future<void>? loadGate;
  final bool loadThrows;
  final bool writeThrows;
  final writes = <bool>[];

  @override
  Future<AppSettings> load() async {
    if (loadGate != null) await loadGate;
    if (loadThrows) throw StateError('prefs unreadable');
    return settings;
  }

  @override
  Future<void> setAppLockBiometric({required bool enabled}) async {
    if (writeThrows) throw StateError('prefs write failed');
    writes.add(enabled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async => '';
}

ProviderContainer _container({
  required _FakeAuth auth,
  required SettingsRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      biometricAuthenticatorProvider.overrideWithValue(auth),
      settingsRepositoryProvider.overrideWith((ref) async => repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AppLockController _ctrl(ProviderContainer c) =>
    c.read(appLockControllerProvider.notifier);
AppLockPhase _phase(ProviderContainer c) =>
    c.read(appLockControllerProvider).phase;

/// Lets queued microtasks/futures run (fakes complete synchronously-ish).
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const lockOn = AppSettings(appLockBiometric: true);
  const lockOff = AppSettings.defaults; // appLockBiometric: false

  group('splash → first phase', () {
    test('starts in splash', () {
      final c = _container(
        auth: _FakeAuth(result: true),
        repo: _ScriptedSettingsRepo(settings: lockOff),
      );
      expect(_phase(c), AppLockPhase.splash);
    });

    test('gate OFF: unlocked without a prompt', () async {
      final auth = _FakeAuth(result: true);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOff),
      );
      await _ctrl(c).onSplashDone();
      expect(_phase(c), AppLockPhase.unlocked);
      expect(auth.prompts, 0);
    });

    test(
      'gate ON + accepted prompt: unlocked after exactly one prompt',
      () async {
        final auth = _FakeAuth(result: true);
        final c = _container(
          auth: auth,
          repo: _ScriptedSettingsRepo(settings: lockOn),
        );
        await _ctrl(c).onSplashDone();
        expect(_phase(c), AppLockPhase.unlocked);
        expect(auth.prompts, 1);
      },
    );

    test(
      'gate ON + rejected prompt: stays locked, no recovery offered',
      () async {
        final auth = _FakeAuth(result: false);
        final c = _container(
          auth: auth,
          repo: _ScriptedSettingsRepo(settings: lockOn),
        );
        await _ctrl(c).onSplashDone();
        final s = c.read(appLockControllerProvider);
        expect(s.phase, AppLockPhase.locked);
        expect(s.noCredential, isFalse);
      },
    );

    test('FAIL-CLOSED: settings load error → locked, never open', () async {
      final auth = _FakeAuth(result: false);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOff, loadThrows: true),
      );
      await _ctrl(c).onSplashDone();
      expect(_phase(c), AppLockPhase.locked);
      expect(auth.prompts, 1);
    });

    test(
      'FAIL-CLOSED: settings still loading → not unlocked until resolved',
      () async {
        final unblock = Completer<void>();
        final auth = _FakeAuth(result: false);
        final c = _container(
          auth: auth,
          repo: _ScriptedSettingsRepo(
            settings: lockOn,
            loadGate: unblock.future,
          ),
        );
        final done = _ctrl(c).onSplashDone();
        await _settle();
        expect(_phase(c), AppLockPhase.splash); // still covered
        unblock.complete();
        await done;
        expect(_phase(c), AppLockPhase.locked);
      },
    );

    test('onSplashDone is idempotent (second call is a no-op)', () async {
      final auth = _FakeAuth(result: true);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOn),
      );
      await _ctrl(c).onSplashDone();
      await _ctrl(c).onSplashDone();
      expect(auth.prompts, 1);
    });
  });

  group('lifecycle re-lock (Q2=B)', () {
    Future<ProviderContainer> unlocked(_FakeAuth auth, AppSettings s) async {
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: s),
      );
      // Settings must be resolved for the runtime `_gateEnabled` read.
      await c.read(settingsControllerProvider.future);
      await _ctrl(c).onSplashDone();
      expect(_phase(c), AppLockPhase.unlocked);
      return c;
    }

    test('paused → locked; resumed → re-prompt; accepted → unlocked', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOn);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
      expect(_phase(c), AppLockPhase.locked);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(auth.prompts, 2);
      expect(_phase(c), AppLockPhase.unlocked);
    });

    test('hidden also locks (Android delivers hidden before paused)', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOn);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.hidden);
      expect(_phase(c), AppLockPhase.locked);
    });

    test('inactive (system dialog) does NOT lock', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOn);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.inactive);
      expect(_phase(c), AppLockPhase.unlocked);
    });

    test('resumed with rejected prompt stays locked', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOn);
      auth.result = false;
      _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(_phase(c), AppLockPhase.locked);
    });

    test('gate OFF: lifecycle is ignored entirely', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOff);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(_phase(c), AppLockPhase.unlocked);
      expect(auth.prompts, 0);
    });

    test('lifecycle during splash is ignored (still booting)', () async {
      final auth = _FakeAuth(result: true);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOn),
      );
      _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(_phase(c), AppLockPhase.splash);
      expect(auth.prompts, 0);
    });

    test(
      'suppressed cycle (camera/crop via LockSuppressor) does NOT lock',
      () async {
        final auth = _FakeAuth(result: true);
        final c = await unlocked(auth, lockOn);
        final suppressor = c.read(lockSuppressorProvider.notifier);
        await suppressor.guard(() async {
          _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
          _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed);
        });
        expect(_phase(c), AppLockPhase.unlocked);
        expect(auth.prompts, 1);
        suppressor.resetForTest();
        // A genuine background afterwards locks as usual.
        _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
        expect(_phase(c), AppLockPhase.locked);
      },
    );

    test('overlapping unlock() calls (resume + Unlock tap) share ONE system '
        'prompt; the single result applies', () async {
      final auth = _FakeAuth(result: true);
      final c = await unlocked(auth, lockOn);
      _ctrl(c).onAppLifecycleState(AppLifecycleState.paused);
      auth.gate = Completer<void>();
      final first = _ctrl(c).unlock(); // prompt is now open
      _ctrl(c).onAppLifecycleState(AppLifecycleState.resumed); // 2nd trigger
      final third = _ctrl(c).unlock(); // user taps Unlock too
      // 1 prompt at splash + exactly 1 now: never stack system prompts.
      expect(auth.prompts, 2);
      auth.gate!.complete();
      await Future.wait([first, third]);
      await _settle();
      expect(_phase(c), AppLockPhase.unlocked);
      expect(auth.prompts, 2);
    });
  });

  group('unlock() and recovery (Q5)', () {
    Future<ProviderContainer> locked(
      _FakeAuth auth, {
      bool writeThrows = false,
    }) async {
      final repo = _ScriptedSettingsRepo(
        settings: lockOn,
        writeThrows: writeThrows,
      );
      final c = _container(auth: auth, repo: repo);
      await c.read(settingsControllerProvider.future);
      await _ctrl(c).onSplashDone(); // first prompt rejected → locked
      expect(_phase(c), AppLockPhase.locked);
      return c;
    }

    test('unlock() when already unlocked is a no-op (no prompt)', () async {
      final auth = _FakeAuth(result: true);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOff),
      );
      await _ctrl(c).onSplashDone();
      await _ctrl(c).unlock();
      expect(auth.prompts, 0);
    });

    test('rejected prompt on a device WITH a credential: noCredential stays '
        'false (no escape hatch)', () async {
      final auth = _FakeAuth(result: false);
      final c = await locked(auth);
      await _ctrl(c).unlock();
      expect(c.read(appLockControllerProvider).noCredential, isFalse);
    });

    test('rejected prompt on a device with NO screen lock: noCredential '
        'true, still locked', () async {
      final auth = _FakeAuth(result: false)
        ..credentialStatus = DeviceCredentialStatus.noneConfigured;
      final c = await locked(auth);
      final s = c.read(appLockControllerProvider);
      expect(s.phase, AppLockPhase.locked);
      expect(s.noCredential, isTrue);
    });

    test('a later accepted prompt clears noCredential', () async {
      final auth = _FakeAuth(result: false)
        ..credentialStatus = DeviceCredentialStatus.noneConfigured;
      final c = await locked(auth);
      auth.result = true;
      await _ctrl(c).unlock();
      expect(
        c.read(appLockControllerProvider),
        const AppLockState(phase: AppLockPhase.unlocked),
      );
    });

    test('disableAppLock persists OFF, then unlocks', () async {
      final auth = _FakeAuth(result: false)
        ..credentialStatus = DeviceCredentialStatus.noneConfigured;
      final c = await locked(auth);
      await _ctrl(c).disableAppLock();
      expect(_phase(c), AppLockPhase.unlocked);
      expect(
        c.read(settingsControllerProvider).valueOrNull?.appLockBiometric,
        isFalse,
      );
    });

    test(
      'FAIL-CLOSED: disableAppLock whose persist fails stays locked',
      () async {
        final auth = _FakeAuth(result: false)
          ..credentialStatus = DeviceCredentialStatus.noneConfigured;
        final c = await locked(auth, writeThrows: true);
        await _ctrl(c).disableAppLock();
        expect(_phase(c), AppLockPhase.locked);
      },
    );

    test('disableAppLock is a no-op unless locked', () async {
      final auth = _FakeAuth(result: true);
      final c = _container(
        auth: auth,
        repo: _ScriptedSettingsRepo(settings: lockOn),
      );
      await _ctrl(c).disableAppLock(); // still in splash
      expect(_phase(c), AppLockPhase.splash);
      expect(
        c.read(settingsControllerProvider).valueOrNull?.appLockBiometric,
        isNot(isFalse),
      );
    });
  });
}
