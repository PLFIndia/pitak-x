import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_cameras.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/core/widgets/camera_scan_view.dart';

import '../../support/a11y.dart';
import '../../support/fake_scan_camera.dart';

/// Review finding P4-M8: the one widget both scan pages show their camera
/// through, in every state it has.
///
/// Before it, a scan page whose camera could not start stayed empty for
/// good, without a word: no reason, no way to the phone's settings, no way
/// to type the number instead. These tests drive the widget through its
/// three seams (the phone's list of cameras, the way to the settings, the
/// scanner package's widget) and hold what it shows and offers in each
/// state. The scanner package's REAL widget is tried in
/// `test/core/widgets/package_reader_widget_test.dart`.
void main() {
  late FakeDeviceCameras cameras;
  late FakeAppSettingsOpener settings;
  late FakeCameraReader reader;
  late List<String> texts;
  late int byHandTaps;

  setUp(() {
    cameras = FakeDeviceCameras();
    settings = FakeAppSettingsOpener();
    reader = FakeCameraReader();
    texts = <String>[];
    byHandTaps = 0;
  });

  /// The view on a page of its own. [withByHand] is the ISBN scan page,
  /// which has somewhere to type; without it, a QR scan page.
  Future<void> pumpView(
    WidgetTester tester, {
    bool withByHand = false,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceCamerasProvider.overrideWithValue(cameras),
          appSettingsOpenerProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Scan')),
            body: CameraScanView(
              codes: CameraScanCodes.qrCode,
              onText: texts.add,
              onEnterByHand: withByHand ? () => byHandTaps++ : null,
              buildReader: reader.build,
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// The camera plugin's own error for a refused permission.
  CameraException refusal() => CameraException(
    'CameraAccessDenied',
    'Camera access permission was denied.',
  );

  /// The view with the camera refused (the package reported it).
  Future<void> pumpRefused(
    WidgetTester tester, {
    bool withByHand = false,
  }) async {
    await pumpView(tester, withByHand: withByHand);
    reader.cameraFailed(refusal());
    await tester.pumpAndSettle();
  }

  void expectNoSentence() {
    expect(find.text(scanCameraRefusedSentence), findsNothing);
    expect(find.text(scanCameraRefusedHint), findsNothing);
    expect(find.text(scanNoCameraSentence), findsNothing);
    expect(find.text(scanCameraDidNotStartSentence), findsNothing);
  }

  void expectNoButton() {
    expect(find.text(openSettingsLabel), findsNothing);
    expect(find.text(tryAgainLabel), findsNothing);
    expect(find.text(enterByHandLabel), findsNothing);
  }

  group('a phone with a camera that starts', () {
    testWidgets('the scanner is shown, and nothing else', (tester) async {
      await pumpView(tester);

      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expect(reader.started, 1);
      expect(cameras.asks, 1);
      expectNoSentence();
      expectNoButton();
    });

    testWidgets('the camera reports that it started: the scanner stays', (
      tester,
    ) async {
      await pumpView(tester);
      reader.cameraStarted();
      await tester.pumpAndSettle();

      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expect(reader.started, 1);
      expect(reader.disposed, 0);
      expectNoSentence();
    });

    testWidgets('a code that is read is handed on as it is', (tester) async {
      await pumpView(tester);

      reader
        ..read('9780306406157')
        ..read('pitaka-lib:0123456789abcdef');

      expect(texts, ['9780306406157', 'pitaka-lib:0123456789abcdef']);
    });

    testWidgets('a system dialog over the app starts no second camera', (
      tester,
    ) async {
      // Android's own permission dialog sends the app away and back. A
      // page that started the camera again at every return would ask in a
      // loop.
      await pumpView(tester);

      await systemDialogOverApp(tester);
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();

      expect(reader.started, 1);
      expect(reader.disposed, 0);
      expect(cameras.asks, 1);
    });
  });

  group('while the phone is asked for its cameras', () {
    testWidgets('no scanner yet, no sentence and no button', (tester) async {
      cameras.hold = true;
      await pumpView(tester, withByHand: true, settle: false);
      await tester.pump();

      expect(cameras.asks, 1);
      expect(reader.started, 0);
      expect(find.text(FakeCameraReader.picture), findsNothing);
      expectNoSentence();
      expectNoButton();

      cameras.release();
      await tester.pumpAndSettle();
      expect(find.text(FakeCameraReader.picture), findsOneWidget);
    });

    testWidgets('an answer that comes after the page was left changes '
        'nothing and throws nothing', (tester) async {
      cameras.hold = true;
      await pumpView(tester, settle: false);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      cameras.release();
      await tester.pumpAndSettle();

      expect(reader.started, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a phone without a camera', () {
    setUp(() => cameras.answer = DeviceCameraAnswer.noCamera);

    testWidgets('says so, and the scanner is never started', (tester) async {
      await pumpView(tester);

      expect(find.text(scanNoCameraSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedSentence), findsNothing);
      expect(find.text(scanCameraDidNotStartSentence), findsNothing);
      expect(reader.started, 0);
      expect(find.text(FakeCameraReader.picture), findsNothing);
    });

    testWidgets('a QR scan page offers no button: there is nothing to do', (
      tester,
    ) async {
      await pumpView(tester);

      expectNoButton();
    });

    testWidgets('the ISBN scan page offers "Enter it by hand" and nothing '
        'else', (tester) async {
      await pumpView(tester, withByHand: true);

      expect(find.text(enterByHandLabel), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      expect(find.text(tryAgainLabel), findsNothing);
    });
  });

  group('a list of cameras that cannot be read', () {
    setUp(() => cameras.answer = DeviceCameraAnswer.unreadable);

    testWidgets('"The camera did not start.", never "no camera"', (
      tester,
    ) async {
      await pumpView(tester);

      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(scanNoCameraSentence), findsNothing);
      expect(reader.started, 0);
    });

    testWidgets('"Try again" asks the phone again and then shows the '
        'scanner', (tester) async {
      await pumpView(tester);
      expect(find.text(tryAgainLabel), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);

      cameras.answer = DeviceCameraAnswer.hasCamera;
      await tester.tap(find.text(tryAgainLabel));
      await tester.pumpAndSettle();

      expect(cameras.asks, 2);
      expect(reader.started, 1);
      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expectNoSentence();
      expectNoButton();
    });

    testWidgets('a port that breaks its promise and throws: the page '
        'still says a sentence', (tester) async {
      cameras.failure = StateError('a port must answer, not throw');
      await pumpView(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(tryAgainLabel), findsOneWidget);
      expect(reader.started, 0);
    });

    testWidgets('"Try again" on a phone that still cannot be read keeps '
        'the sentence', (tester) async {
      await pumpView(tester);

      await tester.tap(find.text(tryAgainLabel));
      await tester.pumpAndSettle();

      expect(cameras.asks, 2);
      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(tryAgainLabel), findsOneWidget);
    });
  });

  group('the camera is refused', () {
    testWidgets('both sentences, and the scanner is taken away', (
      tester,
    ) async {
      await pumpRefused(tester);

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedHint), findsOneWidget);
      expect(find.text(FakeCameraReader.picture), findsNothing);
      // Thrown away: the scanner package lets go of the camera.
      expect(reader.disposed, 1);
    });

    testWidgets('"Open settings", and no "Try again"', (tester) async {
      // After the second refusal Android shows no dialog any more: "Try
      // again" would do nothing that shows (decision D133).
      await pumpRefused(tester);

      expect(find.text(openSettingsLabel), findsOneWidget);
      expect(find.text(tryAgainLabel), findsNothing);
      expect(find.text(enterByHandLabel), findsNothing);
    });

    testWidgets('the ISBN scan page offers "Enter it by hand" as well', (
      tester,
    ) async {
      await pumpRefused(tester, withByHand: true);

      expect(find.text(openSettingsLabel), findsOneWidget);
      expect(find.text(enterByHandLabel), findsOneWidget);
      expect(find.text(tryAgainLabel), findsNothing);
    });

    testWidgets('where the settings cannot be opened, the sentences stand '
        'without that button', (tester) async {
      settings.isAvailable = false;
      await pumpRefused(tester, withByHand: true);

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedHint), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      expect(find.text(enterByHandLabel), findsOneWidget);
    });

    for (final code in [
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    ]) {
      testWidgets('the code "$code" is a refusal too', (tester) async {
        await pumpView(tester);
        reader.cameraFailed(CameraException(code, 'x'));
        await tester.pumpAndSettle();

        expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      });
    }
  });

  group('"Open settings" and the way back', () {
    testWidgets('the tap opens the settings once and changes nothing on '
        'the page', (tester) async {
      await pumpRefused(tester);

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();

      expect(settings.openCalls, 1);
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(cameras.asks, 1);
      expect(reader.started, 1);
    });

    testWidgets('back from the settings the camera is tried again by '
        'itself, once', (tester) async {
      // The scanner package never tries again by itself; without this the
      // page stayed dead until it was left and opened again.
      await pumpRefused(tester);
      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();

      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();

      expect(cameras.asks, 2);
      expect(reader.started, 2);
      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expectNoSentence();

      // A second return starts nothing more.
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(cameras.asks, 2);
      expect(reader.started, 2);
    });

    testWidgets('nothing is tried while the app is still in the '
        'background', (tester) async {
      // The camera must not be started behind the phone's settings.
      await pumpRefused(tester);
      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(cameras.asks, 1, reason: '$state');
        expect(reader.started, 1, reason: '$state');
      }

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(cameras.asks, 1, reason: '$state');
      }

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(cameras.asks, 2);
      expect(reader.started, 2);
    });

    testWidgets('still refused after the settings: the sentences again, '
        'and the next return tries nothing by itself', (tester) async {
      await pumpRefused(tester);
      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(reader.started, 2);

      reader.cameraFailed(refusal());
      await tester.pumpAndSettle();
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);

      // Android's dialog, or the user looking at another app: no loop.
      await systemDialogOverApp(tester);
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(reader.started, 2);
      expect(cameras.asks, 2);
    });

    testWidgets('a second tap while the settings are on their way opens '
        'them once', (tester) async {
      await pumpRefused(tester);
      // The first opening has not answered yet when the second tap comes.
      settings.hold = true;

      await tester.tap(find.text(openSettingsLabel));
      await tester.tap(find.text(openSettingsLabel));
      await tester.pump();
      expect(settings.openCalls, 1);

      settings.release();
      await tester.pumpAndSettle();
      expect(settings.openCalls, 1);
    });

    testWidgets('a return that comes before the opening has answered is '
        'the return that counts', (tester) async {
      await pumpRefused(tester);
      settings.hold = true;
      await tester.tap(find.text(openSettingsLabel));
      await tester.pump();

      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(cameras.asks, 2);
      expect(reader.started, 2);

      // The late answer leaves no memory behind: the next return, which
      // has nothing to do with the settings, tries nothing.
      settings.release();
      await tester.pumpAndSettle();
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(cameras.asks, 2);
      expect(reader.started, 2);
    });

    testWidgets('after a return that changed nothing, "Open settings" '
        'works again', (tester) async {
      await pumpRefused(tester);
      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      reader.cameraFailed(refusal());
      await tester.pumpAndSettle();

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();
      expect(settings.openCalls, 2);

      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(reader.started, 3);
    });

    testWidgets('a return to the app WITHOUT "Open settings" tries '
        'nothing', (tester) async {
      await pumpRefused(tester);

      await systemDialogOverApp(tester);
      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();

      expect(cameras.asks, 1);
      expect(reader.started, 1);
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
    });

    testWidgets('settings that could not be opened: the page keeps its '
        'sentences, and a later return tries nothing', (tester) async {
      settings.opens = false;
      await pumpRefused(tester);

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();
      expect(settings.openCalls, 1);
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedHint), findsOneWidget);

      await leaveAppAndReturn(tester);
      await tester.pumpAndSettle();
      expect(cameras.asks, 1);
      expect(reader.started, 1);
    });
  });

  group('the camera did not start', () {
    Future<void> pumpFailed(
      WidgetTester tester, {
      bool withByHand = false,
    }) async {
      await pumpView(tester, withByHand: withByHand);
      reader.cameraFailed(CameraException('cameraUnavailable', 'in use'));
      await tester.pumpAndSettle();
    }

    testWidgets('the sentence, "Try again", and no "Open settings"', (
      tester,
    ) async {
      await pumpFailed(tester);

      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedSentence), findsNothing);
      expect(find.text(tryAgainLabel), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      expect(find.text(enterByHandLabel), findsNothing);
      expect(reader.disposed, 1);
    });

    testWidgets('the ISBN scan page offers "Enter it by hand" as well', (
      tester,
    ) async {
      await pumpFailed(tester, withByHand: true);

      expect(find.text(tryAgainLabel), findsOneWidget);
      expect(find.text(enterByHandLabel), findsOneWidget);
    });

    testWidgets('"Try again" throws the scanner away and starts a new '
        'one', (tester) async {
      await pumpFailed(tester);

      await tester.tap(find.text(tryAgainLabel));
      await tester.pumpAndSettle();

      expect(cameras.asks, 2);
      expect(reader.started, 2);
      expect(reader.disposed, 1);
      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expectNoSentence();
    });

    testWidgets('after "Try again" the old sentence and its buttons are '
        'gone while the phone is asked', (tester) async {
      await pumpFailed(tester, withByHand: true);
      cameras.hold = true;

      await tester.tap(find.text(tryAgainLabel));
      await tester.pump();

      expect(cameras.asks, 2);
      expectNoSentence();
      expectNoButton();

      cameras.release();
      await tester.pumpAndSettle();
      expect(reader.started, 2);
    });

    testWidgets('an error that is not one of the camera plugin is "did '
        'not start" too', (tester) async {
      await pumpView(tester);
      reader.cameraFailed(Exception('CameraAccessDenied'));
      await tester.pumpAndSettle();

      // The word stands in the TEXT of the exception, not in a code: the
      // text is never read.
      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedSentence), findsNothing);
    });

    testWidgets('a camera that fails after it had started is said too', (
      tester,
    ) async {
      await pumpView(tester);
      reader.cameraStarted();
      await tester.pumpAndSettle();

      reader.cameraFailed(CameraException('cameraClosed', 'gone'));
      await tester.pumpAndSettle();

      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
    });
  });

  group('"Enter it by hand"', () {
    testWidgets('tells the page, once, and the view closes nothing '
        'itself', (tester) async {
      await pumpRefused(tester, withByHand: true);

      await tester.tap(find.text(enterByHandLabel));
      await tester.pumpAndSettle();

      expect(byHandTaps, 1);
      // Still there: closing the page is the page's business.
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(texts, isEmpty);
    });
  });

  group('nothing a plugin says reaches the screen or the log', () {
    /// Runs [body] and answers what was logged meanwhile. The log is put
    /// back inside the test's body: a widget test checks at its end that
    /// `debugPrint` is the one it started with.
    Future<List<String>> logged(Future<void> Function() body) async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        printed.add(message ?? '');
      };
      try {
        await body();
      } finally {
        debugPrint = original;
      }
      return printed;
    }

    testWidgets("the error's text is not shown, and only its code is "
        'logged', (tester) async {
      await pumpView(tester);

      final printed = await logged(() async {
        reader.cameraFailed(
          CameraException('CameraAccessDenied', 'secret text of the plugin'),
        );
        await tester.pumpAndSettle();
      });

      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('CameraAccessDenied'), findsNothing);
      expect(printed, ['camera_scan: camera failed: CameraAccessDenied']);
    });

    testWidgets('an error without a code is logged without its text', (
      tester,
    ) async {
      await pumpView(tester);

      final printed = await logged(() async {
        reader.cameraFailed(Exception('secret text of something else'));
        await tester.pumpAndSettle();
      });

      expect(find.textContaining('secret'), findsNothing);
      expect(printed, ['camera_scan: camera failed']);
    });

    testWidgets('a camera that starts logs nothing', (tester) async {
      final printed = await logged(() async {
        await pumpView(tester);
        reader.cameraStarted();
        await tester.pumpAndSettle();
      });

      expect(printed, isEmpty);
    });
  });

  group('a scanner that calls back after it was thrown away', () {
    testWidgets('after the page was left: nothing happens, nothing is '
        'thrown', (tester) async {
      // The scanner package reports a failed start also when its widget is
      // gone by then (the page was left while the camera started).
      await pumpView(tester);
      await tester.pumpWidget(const SizedBox());

      reader
        ..cameraFailed(refusal())
        ..cameraStarted()
        ..read('9780306406157');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(texts, isEmpty);
    });

    testWidgets('a code from a scanner that was taken away is not handed '
        'on', (tester) async {
      await pumpRefused(tester);

      reader.read('9780306406157');

      expect(texts, isEmpty);
    });

    testWidgets('the scanner of an earlier try does not disturb the one '
        'that runs now', (tester) async {
      await pumpView(tester);
      reader.cameraFailed(CameraException('cameraUnavailable', 'x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tryAgainLabel));
      await tester.pumpAndSettle();
      expect(reader.all, hasLength(2));

      reader.all.first
        ..cameraFailed(refusal())
        ..read('9780306406157');
      await tester.pumpAndSettle();

      expect(find.text(FakeCameraReader.picture), findsOneWidget);
      expectNoSentence();
      expect(texts, isEmpty);

      // The one that runs now is heard.
      reader.read('9780306406157');
      expect(texts, ['9780306406157']);
    });
  });

  group('for a screen reader', () {
    testWidgets('the sentences are one live region, so that they are read '
        'out when they appear', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRefused(tester);

      final node = tester.getSemantics(find.text(scanCameraRefusedSentence));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      expect(
        data.label,
        allOf(
          contains(scanCameraRefusedSentence),
          contains(scanCameraRefusedHint),
        ),
      );
      handle.dispose();
    });

    testWidgets('a refused camera meets the accessibility guidelines', (
      tester,
    ) async {
      await pumpRefused(tester, withByHand: true);

      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('a camera that did not start meets them too', (tester) async {
      cameras.answer = DeviceCameraAnswer.unreadable;
      await pumpView(tester, withByHand: true);
      expect(find.text(tryAgainLabel), findsOneWidget);

      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('a phone without a camera meets them too', (tester) async {
      cameras.answer = DeviceCameraAnswer.noCamera;
      await pumpView(tester, withByHand: true);
      expect(find.text(scanNoCameraSentence), findsOneWidget);

      await expectMeetsA11yGuidelines(tester);
    });
  });

  group('a narrow screen with large text', () {
    // 320 x 480 is the narrowest screen the app is tried on; 2.0 is
    // Android's largest font size. The test font is wider than a real one,
    // so this is the harsher case: what holds here holds on a phone. How
    // many LINES the words take there is not judged here (decision D133's
    // condition is looked at on a device).
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('text scale $scale: nothing overflows, and every button '
          'can be reached and tapped', (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpRefused(tester, withByHand: true);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text(openSettingsLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(openSettingsLabel));
        await tester.pumpAndSettle();
        expect(settings.openCalls, 1);

        await tester.ensureVisible(find.text(enterByHandLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(enterByHandLabel));
        await tester.pumpAndSettle();
        expect(byHandTaps, 1);

        // The other state with two buttons.
        await leaveAppAndReturn(tester);
        await tester.pumpAndSettle();
        reader.cameraFailed(CameraException('cameraUnavailable', 'x'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(tryAgainLabel));
        await tester.pumpAndSettle();
        expect(find.text(tryAgainLabel).hitTestable(), findsOneWidget);
      });
    }
  });
}
