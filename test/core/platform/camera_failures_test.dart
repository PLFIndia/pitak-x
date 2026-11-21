import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/camera_failures.dart';

/// Review finding P4-M8: the two small sortings that turn what a camera
/// plugin reports into the reason the app names on the screen.
///
/// What these tests guard:
///  - a refused camera is recognised by the plugin's own codes, on Android
///    and on iOS;
///  - everything else, a missing code and an unknown code included, never
///    becomes "refused" or "no camera": a wrong reason would send the user
///    to the phone's settings for nothing.
void main() {
  group('scan pages: the code of the camera plugin', () {
    for (final code in [
      // Android (`CameraPermissionsManager.java`) and iOS.
      'CameraAccessDenied',
      // iOS only: refused earlier, the system does not ask again.
      'CameraAccessDeniedWithoutPrompt',
      // iOS only: parental controls and the like.
      'CameraAccessRestricted',
      // The bare beginning, so that the rule is "begins with".
      'CameraAccess',
    ]) {
      test('"$code" is a refused camera', () {
        expect(scanCameraFailureFor(code), ScanCameraFailure.refused);
      });
    }

    for (final code in <String?>[
      null,
      '',
      // Android: a second request while the first dialog is still open.
      'CameraPermissionsRequestOngoing',
      // The plugin's other codes are "the camera did not start".
      'cameraUnavailable',
      'IllegalStateException',
      // Near misses: the rule is exact about case and about where the
      // word stands.
      'cameraAccessDenied',
      'CAMERAACCESSDENIED',
      ' CameraAccessDenied',
      'XCameraAccessDenied',
      'CameraAcces',
      // The cover plugin's word does not belong to this sorting.
      'camera_access_denied',
    ]) {
      test('${code == null ? 'no code' : '"$code"'} is a camera that did '
          'not start', () {
        expect(scanCameraFailureFor(code), ScanCameraFailure.didNotStart);
      });
    }

    test('the sorting never answers "no camera": only the app\'s own '
        'question for the list of cameras can say that', () {
      for (final code in <String?>[
        null,
        '',
        'CameraAccessDenied',
        'no_available_camera',
        'noCamera',
        'cameraNotFound',
      ]) {
        expect(
          scanCameraFailureFor(code),
          isNot(ScanCameraFailure.noCamera),
          reason: '$code',
        );
      }
    });
  });

  group('cover camera: the code of the picker plugin', () {
    test('"camera_access_denied" is a refused camera', () {
      expect(
        coverCameraFailureFor('camera_access_denied'),
        CoverCameraFailure.refused,
      );
    });

    test('"no_available_camera" is a phone without a camera', () {
      expect(
        coverCameraFailureFor('no_available_camera'),
        CoverCameraFailure.noCamera,
      );
    });

    for (final code in <String?>[
      null,
      '',
      // The picker's own code for a second pick while one is open.
      'already_active',
      // Made-up codes: whatever is not one of the two words above.
      'photo_access_denied',
      'crop_error',
      // Near misses: the rule is the exact word.
      'Camera_Access_Denied',
      'camera_access_denied ',
      'camera_access_denied_without_prompt',
      'no_available_cameras',
      // The scanner plugin's word does not belong to this sorting.
      'CameraAccessDenied',
    ]) {
      test('${code == null ? 'no code' : '"$code"'} keeps the general '
          'sentence', () {
        expect(coverCameraFailureFor(code), CoverCameraFailure.other);
      });
    }
  });
}
