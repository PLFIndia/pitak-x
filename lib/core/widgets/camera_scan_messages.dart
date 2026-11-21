/// The words a scan page and the cover camera show when there is no camera
/// picture (core/widgets, review finding P4-M8; decisions D133 to D135).
///
/// Why one file (beginner note): the same sentence stands on two scan pages
/// and in the bar of the cover camera, and the tests ask for it too. Each
/// sentence and each label is a named constant here, so that every place
/// says the same thing in the same words, and a word is changed once.
///
/// Every sentence is the app's own. Nothing a plugin reports is ever shown
/// (AGENTS.md §5).
library;

import 'package:pitaka/core/platform/camera_failures.dart';

/// A scan page, the camera refused: what is the matter.
const String scanCameraRefusedSentence =
    'Pitak is not allowed to use the camera.';

/// A scan page, the camera refused: what to do about it.
const String scanCameraRefusedHint =
    "Allow the camera in the phone's settings to scan.";

/// A scan page on a phone without a camera.
const String scanNoCameraSentence = 'This phone has no camera.';

/// A scan page whose camera could not be started.
const String scanCameraDidNotStartSentence = 'The camera did not start.';

/// The cover camera, for every failure that has no sentence of its own.
const String coverCaptureFailedSentence = 'Could not capture a photo.';

/// The button that opens Pitak's page of the phone's settings.
const String openSettingsLabel = 'Open settings';

/// The button of the ISBN scan page that leads to typing instead.
const String enterByHandLabel = 'Enter it by hand';

/// The button that starts the camera once more.
const String tryAgainLabel = 'Try again';

/// What a screen reader says for the scanner's light button while the
/// light is off. Nothing visible: the button shows an icon.
const String turnOnLightLabel = 'Turn on the light';

/// What a screen reader says for the light button while the light is on.
const String turnOffLightLabel = 'Turn off the light';

/// The sentence a scan page shows for [failure].
String scanCameraSentenceFor(ScanCameraFailure failure) => switch (failure) {
  ScanCameraFailure.refused => scanCameraRefusedSentence,
  ScanCameraFailure.noCamera => scanNoCameraSentence,
  ScanCameraFailure.didNotStart => scanCameraDidNotStartSentence,
};

/// The second sentence a scan page shows for [failure], which says what to
/// do. Only a refused camera has one.
String? scanCameraHintFor(ScanCameraFailure failure) => switch (failure) {
  ScanCameraFailure.refused => scanCameraRefusedHint,
  ScanCameraFailure.noCamera || ScanCameraFailure.didNotStart => null,
};

/// The sentence the cover camera's bar shows for [failure]. The first two
/// are the scan pages' sentences on purpose: one matter, one wording.
String coverCameraSentenceFor(CoverCameraFailure failure) => switch (failure) {
  CoverCameraFailure.refused => scanCameraRefusedSentence,
  CoverCameraFailure.noCamera => scanNoCameraSentence,
  CoverCameraFailure.other => coverCaptureFailedSentence,
};
