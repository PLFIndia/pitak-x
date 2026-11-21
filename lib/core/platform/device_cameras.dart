/// "Does this phone have a camera?", the app's own question (core/platform,
/// review finding P4-M8, decision D130).
///
/// Why this exists (beginner note): the scanner package the scan pages use
/// starts the camera by itself. On a phone WITHOUT a camera, and on a phone
/// whose list of cameras cannot be read, it shows an empty page and tells
/// nobody. So the app asks for the list itself, first, and can then say
/// "This phone has no camera." instead of showing nothing.
///
/// Same seam pattern as `device_resources.dart`: an injectable interface, a
/// plugin-backed implementation, and fail-safe degradation. Whatever goes
/// wrong is "could not be read", never "no camera": the sentence "This
/// phone has no camera." is only said when the phone answered with an empty
/// list.
///
/// Asking for the list starts no camera and takes no picture. On Android it
/// needs no permission (seen on a phone on 2026-11-21: the list was
/// answered with the camera permission refused).
///
/// Privacy: the answer is one of three words. No name of a camera is kept,
/// logged or sent.
library;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/core/platform/app_log.dart';

/// What the phone said about its cameras.
enum DeviceCameraAnswer {
  /// At least one camera is there.
  hasCamera,

  /// The phone answered, and its list of cameras is empty.
  noCamera,

  /// The list could not be read. Not the same as "no camera".
  unreadable,
}

/// Asks the phone whether it has a camera.
// One method on purpose: the port has one job.
// ignore: one_member_abstracts
abstract interface class DeviceCameras {
  /// The phone's answer. An implementation answers
  /// [DeviceCameraAnswer.unreadable] instead of failing.
  Future<DeviceCameraAnswer> ask();
}

/// [DeviceCameras] backed by the `camera` plugin, the same plugin the
/// scanner package uses: the app and the scanner see the same list.
final class PluginDeviceCameras implements DeviceCameras {
  /// Creates the plugin-backed port. [listCameras] is the plugin's own
  /// `availableCameras`; a unit test hands in a list of its own.
  const PluginDeviceCameras({
    Future<List<CameraDescription>> Function() listCameras = availableCameras,
  }) : _listCameras = listCameras;

  final Future<List<CameraDescription>> Function() _listCameras;

  @override
  Future<DeviceCameraAnswer> ask() async {
    try {
      final cameras = await _listCameras();
      return cameras.isEmpty
          ? DeviceCameraAnswer.noCamera
          : DeviceCameraAnswer.hasCamera;
    } on MissingPluginException {
      // No camera plugin on this platform (desktop, tests): expected, and
      // it means "could not be read".
      return DeviceCameraAnswer.unreadable;
    } on CameraException catch (e) {
      // Debug builds log the error CODE only, never its text (release
      // builds log nothing).
      appLog('device_cameras: list failed: ${e.code}');
      return DeviceCameraAnswer.unreadable;
    } on PlatformException catch (e) {
      appLog('device_cameras: list failed: ${e.code}');
      return DeviceCameraAnswer.unreadable;
    } on Object {
      // Everything a plugin can throw, an Error included, ends here on
      // purpose (fail safe): if this call failed, the scan page would wait
      // for its answer for ever and show nothing, which is the very fault
      // this file is there to remove. The page says "The camera did not
      // start." and offers "Try again".
      appLog('device_cameras: list failed');
      return DeviceCameraAnswer.unreadable;
    }
  }
}
