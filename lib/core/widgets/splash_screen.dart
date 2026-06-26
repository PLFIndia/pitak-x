/// Launch/splash branding screen (presentation, AGENTS.md §3.1).
///
/// Shown for ~1 second on launch (and after a successful biometric gate) before
/// the Library screen. Layout per product spec:
///  - a large logo centred on screen — the user's library logo if set, else the
///    default Pitak icon;
///  - a small Pitak icon near the bottom;
///  - below the small icon, the word "Pitak" in Ashokan Brahmi, rendered with
///    the bundled Noto Sans Brahmi font.
///
/// Pure presentation: it calls `onDone` after `holdDuration`. It holds no state
/// beyond the timer and never blocks on data.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/library_logo.dart';

// Ashokan Brahmi spelling of "Pitak" (verified from the Kotlin app's welcome
// screen): U+11027 U+1103A U+1101D U+11013.
/// Brahmi text shown on the splash screen.
const String kPitakBrahmi = '\u{11027}\u{1103A}\u{1101D}\u{11013}';

/// Family name registered in pubspec for the bundled Noto Sans Brahmi font.
const String kBrahmiFontFamily = 'NotoSansBrahmi';

/// The launch/splash screen. Calls [onDone] once [holdDuration] elapses.
class SplashScreen extends StatefulWidget {
  /// Creates the splash. [onDone] fires after [holdDuration] (default ~1s).
  const SplashScreen({
    required this.onDone,
    this.holdDuration = const Duration(seconds: 2),
    super.key,
  });

  /// Called once the hold elapses (transition to the Library).
  final VoidCallback onDone;

  /// How long the splash stays before transitioning.
  final Duration holdDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.holdDuration, widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Big logo, centred: user's library logo when set, else default.
            const Center(child: LibraryLogo(size: 128, borderRadius: 28)),
            // Small Pitak icon + Brahmi name near the bottom.
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The small mark is always the Pitak app icon (brand), not
                    // the user logo — so the brand shows even when a custom
                    // library logo fills the centre.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        kDefaultLogoAsset,
                        width: 40,
                        height: 40,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kPitakBrahmi,
                      style: TextStyle(
                        fontFamily: kBrahmiFontFamily,
                        fontSize: 32,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
