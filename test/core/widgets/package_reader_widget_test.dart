import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/core/widgets/camera_scan_view.dart';
import 'package:pitaka/core/widgets/qr_scan_page.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';

import '../../support/fake_camera_platform.dart';
import '../../support/fake_scan_camera.dart';

/// THE ONE PLACE where a test builds the scanner package's REAL widget
/// (`flutter_zxing`'s `ReaderWidget`), over a stand-in camera (review
/// finding P4-M8, decision D136).
///
/// Why it exists (beginner note): every other test of the scan pages
/// replaces the package's widget, because a test has no camera. Those tests
/// say what the APP does with what the package tells it. They cannot say
/// whether the package still tells it. This file can: it runs the package's
/// own code, and only the camera underneath is played
/// (`test/support/fake_camera_platform.dart`).
///
/// What the app relies on in the package, and what is held here:
///  1. a camera that cannot start is REPORTED (through
///     `onControllerCreated`). Without that report a refused camera leaves
///     the scan page empty without a word, which is the finding itself;
///  2. a widget that is built anew starts the camera again. The package
///     never tries again by itself after a failed start;
///  3. the light button takes the words given to its icons, and shows the
///     icon that belongs to the light's state; the switch-camera button is
///     gone when it is switched off;
///  4. each scan page hands the package the settings it had before.
///
/// WHEN THIS FILE FAILS AFTER AN UPDATE OF `flutter_zxing` (Dependabot will
/// propose one; decision D129 put it off): the package changed something
/// the scan pages rest on. Do not adjust the expectation to make it pass.
/// Read `lib/core/widgets/camera_scan_view.dart`, read the package's
/// `reader_widget.dart` again, and decide what the shared widget has to do
/// now. Then move this test on purpose.
///
/// The package's widget waits for a worker in real time and for timers of
/// the test's own clock. So every wait below is a loop with an upper bound
/// that asks whether the thing happened. Nothing here measures how long
/// anything took.
void main() {
  /// The scan view with the package's real widget, over [camera].
  Future<FakeAppSettingsOpener> pumpRealView(
    WidgetTester tester,
    FakeCameraPlatform camera, {
    CameraScanCodes codes = CameraScanCodes.qrCode,
  }) async {
    installFakeCameraPlatform(camera);
    final settings = FakeAppSettingsOpener();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appSettingsOpenerProvider.overrideWithValue(settings)],
        child: MaterialApp(
          home: Scaffold(
            body: CameraScanView(codes: codes, onText: (_) {}),
          ),
        ),
      ),
    );
    return settings;
  }

  /// Lets real time and the test's clock pass, in turns, until [done] says
  /// yes. Bounded: after the last turn the test goes on and its next
  /// expectation says what is missing.
  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var turn = 0; turn < 60 && !done(); turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Takes the page away and gives the package's widget the time to let go
  /// of its worker and its timers, so that none outlives the test.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var turn = 0; turn < 4; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  group('1. a camera that cannot start is reported to the app', () {
    testWidgets('a refused camera: the page says so and offers the '
        'settings', (tester) async {
      final camera = FakeCameraPlatform(
        startFailure: CameraException('CameraAccessDenied', 'denied'),
      );
      await pumpRealView(tester, camera);

      await waitUntil(tester, () => shows(scanCameraRefusedSentence));

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(scanCameraRefusedHint), findsOneWidget);
      expect(find.text(openSettingsLabel), findsOneWidget);
      expect(camera.startCalls, 1);
      // The package's widget is gone with its camera.
      expect(find.byType(ReaderWidget), findsNothing);
      await leave(tester);
    });

    testWidgets('a camera that fails for another reason: "The camera did '
        'not start."', (tester) async {
      final camera = FakeCameraPlatform(
        startFailure: CameraException('cameraUnavailable', 'in use'),
      );
      await pumpRealView(tester, camera);

      await waitUntil(tester, () => shows(scanCameraDidNotStartSentence));

      expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
      expect(find.text(tryAgainLabel), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a phone without a camera is caught by the app BEFORE the '
        "package's widget is built", (tester) async {
      // The package reports nothing for an empty list of cameras. The
      // app's own question answers first.
      final camera = FakeCameraPlatform(cameras: const []);
      await pumpRealView(tester, camera);

      await waitUntil(tester, () => shows(scanNoCameraSentence));

      expect(find.text(scanNoCameraSentence), findsOneWidget);
      expect(find.byType(ReaderWidget), findsNothing);
      expect(camera.startCalls, 0);
      await leave(tester);
    });
  });

  group('2. a widget that is built anew starts the camera again', () {
    testWidgets('"Try again" after a failed start', (tester) async {
      final camera = FakeCameraPlatform(
        startFailure: CameraException('cameraUnavailable', 'in use'),
      );
      await pumpRealView(tester, camera);
      await waitUntil(tester, () => shows(tryAgainLabel));
      expect(camera.startCalls, 1);

      await tester.tap(find.text(tryAgainLabel));
      await waitUntil(tester, () => camera.startCalls == 2);

      expect(camera.startCalls, 2);
      await waitUntil(tester, () => shows(tryAgainLabel));
      await leave(tester);
    });

    testWidgets('the return from the settings after a refusal', (tester) async {
      final camera = FakeCameraPlatform(
        startFailure: CameraException('CameraAccessDenied', 'denied'),
      );
      final settings = await pumpRealView(tester, camera);
      await waitUntil(tester, () => shows(openSettingsLabel));

      await tester.tap(find.text(openSettingsLabel));
      await tester.pump();
      expect(settings.openCalls, 1);
      await leaveAppAndReturn(tester);
      await waitUntil(tester, () => camera.startCalls == 2);

      expect(camera.startCalls, 2);
      await waitUntil(tester, () => shows(openSettingsLabel));
      await leave(tester);
    });
  });

  group('3. the two built-in buttons', () {
    /// What a screen reader is given for the one button that is left.
    String lightWords(WidgetTester tester) =>
        tester.getSemantics(find.byType(IconButton)).label;

    /// Taps the light button the way a PHONE takes it: the tap is drawn,
    /// frames pass, and only then the phone answers that the light has
    /// changed.
    ///
    /// Why not simply "tap and look" (beginner note): the package draws
    /// its button again at the moment of the tap, BEFORE the phone has
    /// answered, and so with the state the light is about to leave. A
    /// stand-in that answers in the same moment hides that; the first form
    /// of this test did, and the fault was found in an emulator instead
    /// (decision D140).
    Future<void> tapLight(
      WidgetTester tester,
      FakeCameraPlatform camera,
    ) async {
      final before = camera.flashModes.length;
      camera.holdLight = true;
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(camera.flashModes, hasLength(before + 1));
      camera.releaseLight();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      camera.holdLight = false;
    }

    testWidgets('the switch-camera button is gone, and the light button '
        'says what a tap does, also when the phone answers late', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final camera = FakeCameraPlatform();
      await pumpRealView(tester, camera);
      // The package switches the light off once the camera runs.
      await waitUntil(tester, () => camera.flashModes.isNotEmpty);
      expect(camera.flashModes, [FlashMode.off]);

      // ONE button is left of the package's two.
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byIcon(Icons.switch_camera), findsNothing);
      expect(lightWords(tester), turnOnLightLabel);
      final node = tester.getSemantics(find.byType(IconButton));
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);

      // The light goes on: the words turn round, and so does the icon.
      await tapLight(tester, camera);
      expect(camera.flashModes.last, FlashMode.torch);
      expect(lightWords(tester), turnOffLightLabel);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);

      // Off again.
      await tapLight(tester, camera);
      expect(camera.flashModes.last, FlashMode.off);
      expect(lightWords(tester), turnOnLightLabel);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);

      // And on once more: the words are never one tap behind.
      await tapLight(tester, camera);
      expect(camera.flashModes.last, FlashMode.torch);
      expect(lightWords(tester), turnOffLightLabel);

      handle.dispose();
      await leave(tester);
    });

    testWidgets('after the app was in the background the package starts a '
        'new camera, and the words follow THAT one', (tester) async {
      final handle = tester.ensureSemantics();
      final camera = FakeCameraPlatform();
      await pumpRealView(tester, camera);
      await waitUntil(tester, () => camera.flashModes.isNotEmpty);
      expect(camera.startCalls, 1);

      await leaveAppAndReturn(tester);
      await waitUntil(tester, () => camera.startCalls == 2);
      expect(camera.startCalls, 2);
      await waitUntil(tester, () => camera.flashModes.length == 2);
      expect(lightWords(tester), turnOnLightLabel);

      await tapLight(tester, camera);
      expect(camera.flashModes.last, FlashMode.torch);
      expect(lightWords(tester), turnOffLightLabel);

      handle.dispose();
      await leave(tester);
    });

    testWidgets('the page left right after the app came back: the camera '
        'the package is still letting go of disturbs nothing', (tester) async {
      final camera = FakeCameraPlatform();
      await pumpRealView(tester, camera);
      await waitUntil(tester, () => camera.flashModes.isNotEmpty);

      await leaveAppAndReturn(tester);
      await waitUntil(tester, () => camera.startCalls == 2);
      // No waiting here: the first camera may still be on its way out.
      await leave(tester);

      expect(tester.takeException(), isNull);
      expect(camera.startCalls, 2);
    });

    group('a camera that is still alive when it is no longer the one', () {
      // The shared widget watches the camera the package hands over. The
      // package lets go of a camera a moment after it stopped using it,
      // and a camera reports that too. Whatever such a camera reports must
      // not reach a page that is gone, nor count once the package has
      // handed over another. Here the test hands cameras of its own to the
      // callback the package was given, so that the moment is certain.
      CameraController ownCamera() {
        final camera = CameraController(fakeBackCamera, ResolutionPreset.low);
        addTearDown(camera.dispose);
        return camera;
      }

      void lightChanges(CameraController camera) =>
          camera.value = camera.value.copyWith(flashMode: FlashMode.torch);

      Future<ReaderWidget> runningReader(WidgetTester tester) async {
        final camera = FakeCameraPlatform();
        await pumpRealView(tester, camera);
        await waitUntil(tester, () => camera.flashModes.isNotEmpty);
        return tester.widget<ReaderWidget>(find.byType(ReaderWidget));
      }

      testWidgets('after the page was left it reports to nobody', (
        tester,
      ) async {
        final reader = await runningReader(tester);
        final mine = ownCamera();
        reader.onControllerCreated!(mine, null);

        await leave(tester);
        lightChanges(mine);
        await tester.pump();

        expect(tester.takeException(), isNull);
      });

      testWidgets('once another camera was handed over, the one before is '
          'let go of', (tester) async {
        final reader = await runningReader(tester);
        final first = ownCamera();
        final second = ownCamera();
        reader.onControllerCreated!(first, null);
        reader.onControllerCreated!(second, null);

        await leave(tester);
        lightChanges(first);
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a camera that runs shows no sentence, and is let go when '
        'the page is left', (tester) async {
      final camera = FakeCameraPlatform();
      await pumpRealView(tester, camera);
      await waitUntil(tester, () => camera.flashModes.isNotEmpty);

      expect(find.byType(ReaderWidget), findsOneWidget);
      expect(find.text(scanCameraRefusedSentence), findsNothing);
      expect(find.text(scanCameraDidNotStartSentence), findsNothing);
      expect(find.text(scanNoCameraSentence), findsNothing);
      expect(camera.startCalls, 1);

      await leave(tester);
      await waitUntil(tester, () => camera.disposeCalls == 1);
      expect(camera.disposeCalls, 1);
    });
  });

  group('4. each scan page hands the package its own settings', () {
    Future<ReaderWidget> readerOf(WidgetTester tester, Widget page) async {
      final camera = FakeCameraPlatform();
      installFakeCameraPlatform(camera);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsOpenerProvider.overrideWithValue(
              FakeAppSettingsOpener(),
            ),
          ],
          child: MaterialApp(home: page),
        ),
      );
      await waitUntil(
        tester,
        () => find.byType(ReaderWidget).evaluate().isNotEmpty,
      );
      return tester.widget<ReaderWidget>(find.byType(ReaderWidget));
    }

    void expectCommon(ReaderWidget reader) {
      expect(reader.onControllerCreated, isNotNull);
      expect(reader.onScan, isNotNull);
      expect(reader.showGallery, isFalse);
      expect(reader.showToggleCamera, isFalse);
      expect(reader.showFlashlight, isTrue);
      expect(reader.scanDelaySuccess, const Duration(milliseconds: 500));
      // The words of the light, for every mode the package has an icon
      // for. Its button only ever switches between "off" and "torch"
      // (group 3 shows both on the screen); "auto" and "always" get words
      // all the same, so that no mode is ever left without.
      String? wordsOf(Widget icon) => (icon as Icon).semanticLabel;
      expect(wordsOf(reader.flashOnIcon), turnOffLightLabel);
      expect(wordsOf(reader.flashOffIcon), turnOnLightLabel);
      expect(wordsOf(reader.flashAutoIcon), turnOnLightLabel);
      expect(wordsOf(reader.flashAlwaysIcon), turnOnLightLabel);
      // Left as the package has them.
      expect(reader.isMultiScan, isFalse);
      expect(reader.lensDirection, CameraLensDirection.back);
      expect(reader.resolution, ResolutionPreset.high);
    }

    testWidgets('the ISBN scan page: EAN barcodes, the wide crop and the '
        'thorough passes', (tester) async {
      final reader = await readerOf(tester, const ScannerPage());

      expectCommon(reader);
      expect(reader.codeFormat, Format.ean13 | Format.ean8);
      expect(reader.cropPercent, 0.9);
      expect(reader.tryHarder, isTrue);
      expect(reader.tryInverted, isTrue);
      expect(reader.tryDownscale, isTrue);
      expect(reader.scanDelay, const Duration(milliseconds: 300));
      await leave(tester);
    });

    testWidgets("a QR scan page: QR codes, with the package's own "
        'defaults', (tester) async {
      final reader = await readerOf(
        tester,
        QrScanPage<String>(title: 'Scan a library QR', accept: (raw) => raw),
      );

      expectCommon(reader);
      expect(reader.codeFormat, Format.qrCode);
      // What `ReaderWidget()` has when nothing is said: the QR pages said
      // nothing before, and must read as they did.
      const untouched = ReaderWidget();
      expect(reader.cropPercent, untouched.cropPercent);
      expect(reader.tryHarder, untouched.tryHarder);
      expect(reader.tryInverted, untouched.tryInverted);
      expect(reader.tryDownscale, untouched.tryDownscale);
      expect(reader.scanDelay, untouched.scanDelay);
      await leave(tester);
    });

    testWidgets('only a valid code with a text is handed to the page', (
      tester,
    ) async {
      final camera = FakeCameraPlatform();
      installFakeCameraPlatform(camera);
      final texts = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsOpenerProvider.overrideWithValue(
              FakeAppSettingsOpener(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CameraScanView(
                codes: CameraScanCodes.qrCode,
                onText: texts.add,
              ),
            ),
          ),
        ),
      );
      await waitUntil(
        tester,
        () => find.byType(ReaderWidget).evaluate().isNotEmpty,
      );
      final onScan = tester
          .widget<ReaderWidget>(find.byType(ReaderWidget))
          .onScan!;

      // What the package's decoder can hand over.
      onScan(Code(text: 'not valid'));
      onScan(Code(isValid: true));
      onScan(Code(text: 'pitaka-lib:0123456789abcdef', isValid: true));

      expect(texts, ['pitaka-lib:0123456789abcdef']);
      await leave(tester);
    });
  });
}
