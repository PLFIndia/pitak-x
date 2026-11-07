import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/app_lock/app_lock_observer.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/widgets/app_gate.dart';
import 'package:pitaka/core/widgets/edge_to_edge_safe_area.dart';
import 'package:pitaka/core/widgets/root_navigator_key.dart';
import 'package:pitaka/core/widgets/unfocus_on_pause.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/network/presentation/widgets/events_watch_lifecycle_relay.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/presentation/widgets/availability_lifecycle_relay.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/presentation/app_theme_mode_mapper.dart';
import 'package:pitaka/src/rust/frb_generated.dart';

Future<void> main() async {
  // The shipping entry point contains no development harness: the AOT memory
  // scenario lives in `lib/main_dev_harness.dart` and is run with `-t`
  // (fix-plan L15).
  //
  // Load the native pitak_crypto core before any vault operation. Must complete
  // before the FFI surface (unlockAndReadVault) is callable.
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: PitakaApp()));
}

/// Root app shell. Home is the Library list; theme follows user settings.
class PitakaApp extends ConsumerWidget {
  /// Creates the root app shell.
  const PitakaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme follows the persisted setting; defaults to system until loaded.
    final themeMode = ref
        .watch(settingsControllerProvider)
        .maybeWhen(
          data: (s) => s.themeMode.toThemeMode(),
          orElse: () => ThemeMode.system,
        );
    // Screen-capture protection (Android FLAG_SECURE) follows the combined
    // policy app-wide: on while the vault is unlocked (PII visible) OR any
    // passphrase entry field is visible (#34/F-12, REVIEW_FINDINGS_2 S2).
    ref
      ..listen<bool>(screenCaptureProtectedProvider, (previous, secure) {
        if (previous == secure) return;
        ref.read(screenSecurityProvider).setSecure(secure: secure);
      })
      // The availability lane (ADR 0019, plan C.4 "Start"): listening builds
      // its keepAlive notifier once, at app start, so a set saved before the
      // app last closed is retried now (AV17) and a loan made on any screen
      // is published by itself. The notifier decides everything else — it
      // starts nothing while `availabilityLaneActivated` is false — so there
      // is nothing to do with its value here.
      ..listen(availabilityAutoPublisherProvider, (_, _) {})
      // Complete a site restore that committed its catalogue but was
      // interrupted before the public identity preference was saved.
      ..listen(publishedIdentityStartupRecoveryProvider, (_, _) {});

    // AppLockObserver sits ABOVE MaterialApp: it forwards lifecycle events to
    // the app-lock controller and, while locked, intercepts the Android back
    // button before the navigator can pop a route hidden under the lock (B01).
    // AvailabilityLifecycleRelay sits next to it for the same reason (it
    // needs the app's lifecycle, not a route's): it tells the lane when the
    // app returns to the foreground, so a set that could not go out while
    // offline is retried (plan C.4 "Retry triggers").
    // EventsWatchLifecycleRelay (ADR 0024) sits here for the same reason:
    // it bootstraps the event-alert plugins once, reconciles the schedule
    // on start/unlock/resume, and routes a notification tap only after the
    // app lock has been passed.
    return AppLockObserver(
      child: AvailabilityLifecycleRelay(
        child: EventsWatchLifecycleRelay(
          child: MaterialApp(
            navigatorKey: ref.watch(rootNavigatorKeyProvider),
            title: 'Pitak',
            // `builder` wraps the Navigator itself, so both wrappers below
            // apply to EVERY route, dialog and sheet — not just `home`:
            //  - AppGate: splash + optional biometric lock painted OVER the
            //    whole navigator; routes underneath are kept alive but inert
            //    (B01).
            //  - EdgeToEdgeSafeArea: Android 15+ draws the app behind the
            //    system navigation bar; pads all content clear of it once
            //    (decision A).
            builder: (context, child) => AppGate(
              child: EdgeToEdgeSafeArea(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            themeMode: themeMode,
            // Both themes live in lib/core/theme/app_theme.dart so the golden and
            // accessibility tests render exactly what ships.
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            // UnfocusOnPause: releases keyboard focus when the app is
            // backgrounded, so the first tap after resume reliably reopens the
            // keyboard (fixes the stale-IME "tap does nothing" bug) and clears
            // focus off secret fields.
            home: const UnfocusOnPause(child: LibraryPage()),
          ),
        ),
      ),
    );
  }
}
