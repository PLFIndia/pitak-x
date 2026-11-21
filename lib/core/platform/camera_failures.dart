/// Why there is no camera picture: two small sortings (core/platform,
/// review finding P4-M8).
///
/// Why this exists (beginner note): a camera plugin reports a failure as an
/// error with a short CODE, for example `CameraAccessDenied`. The app never
/// shows that code, nor the text that comes with it (AGENTS.md §5). It
/// sorts the code into one of a few reasons, and the screen says a sentence
/// of the app's own for that reason.
///
/// The two plugins use different codes, so there are two sortings:
///  - the scan pages use the `camera` plugin (through the scanner package);
///  - the cover camera uses the `image_picker` plugin.
///
/// The rule both follow: a code that is missing or not known NEVER becomes
/// a specific reason. A wrong "Pitak is not allowed to use the camera"
/// would send the user to the phone's settings for nothing; the general
/// sentence is always true.
///
/// Pure Dart on purpose: no plugin is imported, so the rule is tested
/// without a camera.
library;

/// Why a scan page shows no camera picture.
enum ScanCameraFailure {
  /// The user, or a policy of the phone, does not let Pitak use the camera.
  refused,

  /// The phone has no camera at all. Only the app's own question for the
  /// list of cameras says this (`device_cameras.dart`); no error code does.
  noCamera,

  /// Anything else: the camera could not be started.
  didNotStart,
}

/// Sorts the error [code] of the `camera` plugin for a scan page.
///
/// A refusal is every code that begins with `CameraAccess`. Read in the
/// plugins on 2026-11-21: Android has `CameraAccessDenied`
/// (`camera_android_camerax` 0.7.2, `CameraPermissionsManager.java`); iOS
/// has `CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt` and
/// `CameraAccessRestricted` (`camera_avfoundation` 0.10.1,
/// `CameraPermissionManager.swift`). Android has ONE code for "refused just
/// now" and "refused for good", so the app cannot tell the two apart.
///
/// Never answers [ScanCameraFailure.noCamera].
ScanCameraFailure scanCameraFailureFor(String? code) =>
    code != null && code.startsWith('CameraAccess')
    ? ScanCameraFailure.refused
    : ScanCameraFailure.didNotStart;

/// Why the cover camera took no photo.
enum CoverCameraFailure {
  /// The user, or a policy of the phone, does not let Pitak use the camera.
  refused,

  /// The phone has no camera app that could take the photo.
  noCamera,

  /// Anything else, a failure of the crop step included.
  other,
}

/// Sorts the error [code] of the `image_picker` plugin for the cover
/// camera.
///
/// The two codes are the plugin's own words (`image_picker_android`
/// 0.8.13+17, `ImagePickerDelegate.java`: `camera_access_denied` when the
/// permission is refused, `no_available_camera` when no camera app answers).
/// Only the exact word counts.
CoverCameraFailure coverCameraFailureFor(String? code) => switch (code) {
  'camera_access_denied' => CoverCameraFailure.refused,
  'no_available_camera' => CoverCameraFailure.noCamera,
  _ => CoverCameraFailure.other,
};
