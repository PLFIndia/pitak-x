/// What the app says when the cover camera took no photo (presentation
/// layer; review finding P4-M8, decision D134, ADR 0030).
///
/// Why one file (beginner note): a cover is photographed in two places (the
/// cover field of the forms, "Replace cover" on an item's page). Both
/// answered every failure of the camera with "Could not capture a photo.",
/// a refused permission too, which gave the user nothing to act on. Here
/// the sorting of the failure and the bar exist once.
///
/// What is shown, in the bar at the bottom of the screen:
///  - the camera is refused: "Pitak is not allowed to use the camera." with
///    the button "Open settings", where the phone's settings can be opened;
///  - the phone has no camera: "This phone has no camera.";
///  - anything else, a failure of the crop step included: "Could not
///    capture a photo.", as before.
///
/// Nothing is tried again by itself: after the settings the user taps the
/// cover button again.
///
/// Privacy: only the error's CODE is read. Its text is never shown and
/// never logged.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/camera_failures.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';

/// How long the bar with "Open settings" stays: as long as the "Undo" bar
/// of a returned loan (decision D134, after D114).
const Duration coverCameraSettingsBarDuration = Duration(seconds: 6);

/// Shows the bar for a cover photo that failed with [error] (what the
/// camera or the crop plugin threw).
///
/// Call it while [context] is mounted. The bar belongs to the app's one
/// `ScaffoldMessenger`, so it stays when the page is left; its button needs
/// nothing of the page any more.
void showCoverCameraFailure(BuildContext context, WidgetRef ref, Object error) {
  // The picker plugin reports its reason as the code of a
  // `PlatformException`. Anything else has no code and gets the general
  // sentence.
  final code = error is PlatformException ? error.code : null;
  final failure = coverCameraFailureFor(code);
  // Taken now: the button may be tapped after the page, and its `ref`, are
  // gone. The opener itself keeps no state.
  final settings = ref.read(appSettingsOpenerProvider);
  final offerSettings =
      failure == CoverCameraFailure.refused && settings.isAvailable;
  ScaffoldMessenger.of(context).showSnackBar(
    offerSettings
        ? SnackBar(
            content: Text(coverCameraSentenceFor(failure)),
            duration: coverCameraSettingsBarDuration,
            // Said explicitly: since Flutter 3.38 a bar with an action
            // stays for good unless it is told otherwise, and a bar that
            // stays holds every later message of the app back.
            persist: false,
            action: SnackBarAction(
              label: openSettingsLabel,
              onPressed: () => unawaited(settings.open()),
            ),
          )
        : SnackBar(content: Text(coverCameraSentenceFor(failure))),
  );
}
