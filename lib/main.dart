import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/app_lock/app_lock_observer.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/app_gate.dart';
import 'package:pitaka/core/widgets/edge_to_edge_safe_area.dart';
import 'package:pitaka/core/widgets/unfocus_on_pause.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/presentation/app_theme_mode_mapper.dart';
import 'package:pitaka/src/rust/frb_generated.dart';

Future<void> main() async {
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
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

    // Screen-capture protection (Android FLAG_SECURE) follows the combined
    // policy app-wide: on while the vault is unlocked (PII visible) OR any
    // passphrase entry field is visible (#34/F-12, REVIEW_FINDINGS_2 S2).
    ref.listen<bool>(screenCaptureProtectedProvider, (previous, secure) {
      if (previous == secure) return;
      ref.read(screenSecurityProvider).setSecure(secure: secure);
    });

    // AppLockObserver sits ABOVE MaterialApp: it forwards lifecycle events to
    // the app-lock controller and, while locked, intercepts the Android back
    // button before the navigator can pop a route hidden under the lock (B01).
    return AppLockObserver(
      child: MaterialApp(
        title: 'Pitak',
        // `builder` wraps the Navigator itself, so both wrappers below apply
        // to EVERY route, dialog and sheet — not just `home`:
        //  - AppGate: splash + optional biometric lock painted OVER the whole
        //    navigator; routes underneath are kept alive but inert (B01).
        //  - EdgeToEdgeSafeArea: Android 15+ draws the app behind the system
        //    navigation bar; pads all content clear of it once (decision A).
        builder: (context, child) => AppGate(
          child: EdgeToEdgeSafeArea(child: child ?? const SizedBox.shrink()),
        ),
        themeMode: themeMode,
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        // UnfocusOnPause: releases keyboard focus when the app is
        // backgrounded, so the first tap after resume reliably reopens the
        // keyboard (fixes the stale-IME "tap does nothing" bug) and clears
        // focus off secret fields.
        home: const UnfocusOnPause(child: LibraryPage()),
      ),
    );
  }
}
