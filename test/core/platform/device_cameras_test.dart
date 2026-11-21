import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_cameras.dart';

import '../../support/fake_camera_platform.dart';

/// Review finding P4-M8, decision D130: the app's own question "does this
/// phone have a camera", asked before a scan page shows the scanner.
///
/// Why the app asks (beginner note): the scanner package shows an empty
/// page, without a word, on a phone that has no camera and on a phone whose
/// list of cameras cannot be read. It reports neither. So the app asks
/// first, and says a sentence.
///
/// What these tests guard:
///  - one camera or more is "has a camera"; an empty list is "no camera";
///  - a list that cannot be read is "could not be read", whatever was
///    thrown, and never "no camera": that sentence must be true;
///  - nothing but an error CODE is ever logged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> printed;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    printed = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message ?? '');
    };
  });

  tearDown(() => debugPrint = originalDebugPrint);

  /// The port, asking a list the test decides.
  PluginDeviceCameras camerasThat(
    Future<List<CameraDescription>> Function() list,
  ) => PluginDeviceCameras(listCameras: list);

  test('one camera: the phone has a camera', () async {
    final cameras = camerasThat(() async => const [fakeBackCamera]);

    expect(await cameras.ask(), DeviceCameraAnswer.hasCamera);
    expect(printed, isEmpty);
  });

  test('a front camera alone counts too', () async {
    final cameras = camerasThat(
      () async => const [
        CameraDescription(
          name: '1',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 270,
        ),
      ],
    );

    expect(await cameras.ask(), DeviceCameraAnswer.hasCamera);
  });

  test('an empty list: the phone has no camera', () async {
    final cameras = camerasThat(() async => const []);

    expect(await cameras.ask(), DeviceCameraAnswer.noCamera);
    expect(printed, isEmpty);
  });

  test('the plugin reports an error: could not be read, and only the '
      'error code is logged', () async {
    final cameras = camerasThat(
      () async => throw CameraException(
        'cameraUnavailable',
        'camera 0 of /dev/video0 is held by com.example.other',
      ),
    );

    expect(await cameras.ask(), DeviceCameraAnswer.unreadable);
    expect(printed, ['device_cameras: list failed: cameraUnavailable']);
  });

  test('a platform error: could not be read, and only its code is '
      'logged', () async {
    final cameras = camerasThat(
      () async => throw PlatformException(
        code: 'boom',
        message: 'secret detail',
        details: '/data/user/0/dev.khoj.pitaka',
      ),
    );

    expect(await cameras.ask(), DeviceCameraAnswer.unreadable);
    expect(printed, ['device_cameras: list failed: boom']);
  });

  test('no camera plugin on this platform (desktop, tests): could not be '
      'read, and nothing is logged', () async {
    final cameras = camerasThat(
      () async => throw MissingPluginException('no handler for cameras'),
    );

    expect(await cameras.ask(), DeviceCameraAnswer.unreadable);
    expect(printed, isEmpty);
  });

  test('anything else that is thrown, an Error too: could not be read, '
      'and its text is never logged', () async {
    for (final thrown in <Object>[
      Exception('text of an exception'),
      StateError('text of an error'),
      'a bare string',
    ]) {
      printed.clear();
      // Thrown as it is: the port must take whatever a plugin throws.
      // ignore: only_throw_errors
      final cameras = camerasThat(() async => throw thrown);

      expect(await cameras.ask(), DeviceCameraAnswer.unreadable);
      expect(printed, ['device_cameras: list failed']);
    }
  });

  test(
    'a list that fails before its first wait is taken the same way',
    () async {
      // Not `async`: the throw happens while the call is being made.
      final cameras = camerasThat(() => throw StateError('at once'));

      expect(await cameras.ask(), DeviceCameraAnswer.unreadable);
    },
  );

  test('a failure is never "no camera"', () async {
    for (final thrown in <Object>[
      CameraException('noCamera', 'no camera'),
      MissingPluginException(),
      StateError('x'),
    ]) {
      // ignore: only_throw_errors
      final cameras = camerasThat(() async => throw thrown);

      expect(await cameras.ask(), isNot(DeviceCameraAnswer.noCamera));
    }
  });

  group('left as it is, the port asks the camera plugin', () {
    test('the list of the plugin is the list that counts', () async {
      final none = FakeCameraPlatform(cameras: const []);
      installFakeCameraPlatform(none);
      expect(
        await const PluginDeviceCameras().ask(),
        DeviceCameraAnswer.noCamera,
      );
      expect(none.listCalls, 1);

      final one = FakeCameraPlatform();
      installFakeCameraPlatform(one);
      expect(
        await const PluginDeviceCameras().ask(),
        DeviceCameraAnswer.hasCamera,
      );
      expect(one.listCalls, 1);
      // Asking for the list starts no camera, so it needs no permission.
      expect(one.startCalls, 0);
    });

    test('the provider hands out that port', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(deviceCamerasProvider), isA<PluginDeviceCameras>());
    });
  });
}
