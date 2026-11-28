import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/app_settings_opener.dart';
import 'package:pitaka/core/platform/device_cameras.dart';

/// Stand-ins for everything a scan page's camera rests on (review finding
/// P4-M8): the phone's list of cameras, the way to the phone's settings,
/// and the scanner package's own widget.

/// A [DeviceCameras] for tests: answers [answer] and counts the questions.
///
/// With [hold] set, a question waits until the test lets it go
/// ([release]), so that a test can look at the page while it is asking.
final class FakeDeviceCameras implements DeviceCameras {
  /// Creates the fake. The default is a phone with a camera.
  FakeDeviceCameras({this.answer = DeviceCameraAnswer.hasCamera});

  /// What the next [ask] answers.
  DeviceCameraAnswer answer;

  /// When true, [ask] waits for [release].
  bool hold = false;

  /// When set, [ask] throws this instead of answering (which the port
  /// promises never to do).
  Object? failure;

  /// How many times [ask] was called.
  int asks = 0;

  final List<Completer<void>> _held = [];

  @override
  Future<DeviceCameraAnswer> ask() async {
    asks++;
    final failure = this.failure;
    // A test fake throws whatever the test asks for.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    if (hold) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    return answer;
  }

  /// Lets every waiting question go, with the answer set by then.
  void release() {
    for (final gate in _held) {
      gate.complete();
    }
    _held.clear();
  }
}

/// An [AppSettingsOpener] for tests: counts the openings and answers
/// [opens] ("the page was opened").
///
/// With [hold] set, an opening waits until the test lets it go ([release]):
/// on a phone the answer comes back while the settings are already on
/// their way to the front.
final class FakeAppSettingsOpener implements AppSettingsOpener {
  /// Creates the fake. The default is Android, where the page opens.
  FakeAppSettingsOpener({this.isAvailable = true, this.opens = true});

  @override
  bool isAvailable;

  /// What [open] answers.
  bool opens;

  /// When true, [open] waits for [release].
  bool hold = false;

  /// How many times [open] was called.
  int openCalls = 0;

  final List<Completer<void>> _held = [];

  @override
  Future<bool> open() async {
    openCalls++;
    if (hold) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    return opens;
  }

  /// Lets every waiting opening go.
  void release() {
    for (final gate in _held) {
      gate.complete();
    }
    _held.clear();
  }
}

/// Plays the scanner package's widget behind the seam of `CameraScanView`.
///
/// It shows a marker text in the place of the camera picture and keeps the
/// two callbacks the shared widget handed it, so that a test can say "a
/// code was read" and "the camera started" or "the camera failed". It
/// counts how often such a widget was started and thrown away: every start
/// is a camera that would be opened.
final class FakeCameraReader {
  /// The text that stands in the place of the camera picture.
  static const String picture = 'camera picture';

  /// How many readers were started (one per camera that would be opened).
  int started = 0;

  /// How many readers were thrown away (the camera would be closed).
  int disposed = 0;

  /// Every reader that was started, the oldest first. Kept beyond each
  /// reader's life on purpose: the real package can call back after its
  /// widget was thrown away, and a test tries exactly that.
  final List<FakeReaderHandle> all = [];

  /// The builder to hand to `CameraScanView.buildReader`.
  Widget build(
    void Function(String raw) onText,
    void Function(Exception? error) onCameraResult,
  ) => _FakeReaderWidget(
    log: this,
    onText: onText,
    onCameraResult: onCameraResult,
  );

  /// The newest reader's camera read a code.
  void read(String raw) => all.last.read(raw);

  /// The newest reader's camera started.
  void cameraStarted() => all.last.cameraStarted();

  /// The newest reader's camera failed with [error], as the scanner
  /// package reports it.
  void cameraFailed(Exception error) => all.last.cameraFailed(error);
}

/// The callbacks ONE started reader was handed.
final class FakeReaderHandle {
  FakeReaderHandle._(this._onText, this._onCameraResult);

  final void Function(String raw) _onText;
  final void Function(Exception? error) _onCameraResult;

  /// This reader's camera read a code.
  void read(String raw) => _onText(raw);

  /// This reader's camera started.
  void cameraStarted() => _onCameraResult(null);

  /// This reader's camera failed with [error].
  void cameraFailed(Exception error) => _onCameraResult(error);
}

class _FakeReaderWidget extends StatefulWidget {
  const _FakeReaderWidget({
    required this.log,
    required this.onText,
    required this.onCameraResult,
  });

  final FakeCameraReader log;
  final void Function(String raw) onText;
  final void Function(Exception? error) onCameraResult;

  @override
  State<_FakeReaderWidget> createState() => _FakeReaderWidgetState();
}

class _FakeReaderWidgetState extends State<_FakeReaderWidget> {
  @override
  void initState() {
    super.initState();
    widget.log.started++;
    widget.log.all.add(
      FakeReaderHandle._(widget.onText, widget.onCameraResult),
    );
  }

  @override
  void dispose() {
    widget.log.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text(FakeCameraReader.picture));
}

/// The app goes to the background and comes back, as it does when the user
/// visits the phone's settings.
Future<void> leaveAppAndReturn(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

/// A dialog of the system lies over the app for a moment and goes again,
/// as Android's own "Allow Pitak to take pictures?" dialog does.
Future<void> systemDialogOverApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}
