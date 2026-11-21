import 'dart:async';

// Test-only seam into the camera plugin, in the words of
// `cover_capture_fakes.dart`: the package is already locked transitively;
// keeping it out of pubspec leaves the app's dependency surface unchanged.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera on the back of the phone, as the plugin describes one.
const CameraDescription fakeBackCamera = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// Puts [fake] in the place of the phone's cameras for one test and puts
/// the previous platform back afterwards.
void installFakeCameraPlatform(FakeCameraPlatform fake) {
  final previous = CameraPlatform.instance;
  CameraPlatform.instance = fake;
  addTearDown(() => CameraPlatform.instance = previous);
}

/// Plays the phone's cameras for the camera plugin (review finding P4-M8).
///
/// It answers the two questions the app's code and the scanner package ask
/// before a camera picture exists: which cameras are there, and "start this
/// one". A test decides each answer.
///
/// A camera that is allowed to start then "runs": it reports itself ready,
/// takes the switching of its light, and shows an empty box in the place of
/// its picture. It never produces a frame, so no code is ever read.
final class FakeCameraPlatform extends CameraPlatform {
  /// [cameras] is the list the phone reports. [listFailure] is thrown when
  /// the list is asked for; [startFailure] when a camera is started.
  FakeCameraPlatform({
    this.cameras = const [fakeBackCamera],
    this.listFailure,
    this.startFailure,
  });

  /// The cameras this phone reports.
  final List<CameraDescription> cameras;

  /// Thrown by [availableCameras] when set.
  final Object? listFailure;

  /// Thrown when a camera is started, when set.
  final Object? startFailure;

  /// How often the list of cameras was asked for.
  int listCalls = 0;

  /// How often a camera was asked to start.
  int startCalls = 0;

  /// How often a started camera was let go again.
  int disposeCalls = 0;

  /// Every mode the camera's light was switched to, in order.
  final List<FlashMode> flashModes = [];

  /// When true, a switching of the light is taken at once but ANSWERED
  /// only at [releaseLight]. A phone answers after a few frames, not in
  /// the same moment; a stand-in that answers at once hides whatever goes
  /// wrong in between.
  bool holdLight = false;

  final List<Completer<void>> _heldLight = [];

  /// Answers every switching of the light that is waiting.
  void releaseLight() {
    for (final gate in _heldLight) {
      gate.complete();
    }
    _heldLight.clear();
  }

  @override
  Future<List<CameraDescription>> availableCameras() async {
    listCalls++;
    final failure = listFailure;
    // Thrown as it is, on purpose: a test may hand in an Error too.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    startCalls++;
    final failure = startFailure;
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return 1;
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) => createCameraWithSettings(cameraDescription, null);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  // A stream that never ends and never has an event: the camera plugin
  // waits for the FIRST error of a camera, and an ended stream would be
  // "no element" to it.
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      Completer<CameraErrorEvent>().future.asStream();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => const Stream.empty();

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    flashModes.add(mode);
    if (holdLight) {
      final gate = Completer<void>();
      _heldLight.add(gate);
      await gate.future;
    }
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }
}
