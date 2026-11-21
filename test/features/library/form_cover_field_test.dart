import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';

import '../../support/cover_capture_fakes.dart';
import '../../support/fake_scan_camera.dart';

void main() {
  Widget app(
    CoverCaptureFakes fakes,
    List<String?> changes, {
    List<bool>? busyChanges,
    FakeAppSettingsOpener? settings,
  }) {
    return ProviderScope(
      overrides: [
        coversDirProvider.overrideWith((ref) async => '.'),
        formCoverControllerProvider.overrideWith(() => fakes.controller),
        if (settings != null)
          appSettingsOpenerProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Cover')),
                    body: FormCoverField(
                      title: 'Chess set',
                      coverRef: null,
                      onChanged: changes.add,
                      onBusyChanged: busyChanges?.add ?? (_) {},
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openField(
    WidgetTester tester,
    CoverCaptureFakes fakes,
    List<String?> changes, {
    List<bool>? busyChanges,
    FakeAppSettingsOpener? settings,
  }) async {
    await tester.pumpWidget(
      app(fakes, changes, busyChanges: busyChanges, settings: settings),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // Review finding P4-M8, decision D134: the cover camera answered every
  // failure with "Could not capture a photo.", a refused permission too.
  // The bar itself is tested in `cover_camera_message_test.dart`; here:
  // that this field's capture goes through it.
  group('the cover camera fails', () {
    /// Taps "Add cover" and lets the camera fail with [error].
    Future<void> captureFailing(
      WidgetTester tester,
      CoverCaptureFakes fakes,
      Object error,
    ) async {
      await tester.tap(find.text('Add cover'));
      await tester.pump();
      await fakes.pickerGate.entered;
      fakes.pickerGate.fail(error);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('refused: the sentence says so, with "Open settings"', (
      tester,
    ) async {
      final fakes = installCoverCaptureFakes();
      final settings = FakeAppSettingsOpener();
      final busyChanges = <bool>[];
      await openField(
        tester,
        fakes,
        <String?>[],
        busyChanges: busyChanges,
        settings: settings,
      );

      await captureFailing(
        tester,
        fakes,
        PlatformException(
          code: 'camera_access_denied',
          message: 'The user did not allow camera access.',
        ),
      );

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(coverCaptureFailedSentence), findsNothing);
      expect(find.textContaining('did not allow'), findsNothing);
      // The field is ready for another try; nothing retries by itself.
      expect(busyChanges, [true, false]);
      expect(fakes.picker.calls, 1);
      expect(fakes.cropper.calls, 0);

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();
      expect(settings.openCalls, 1);
      expect(fakes.picker.calls, 1);
    });

    testWidgets('a camera that fails after the form was left shows nothing '
        'and throws nothing', (tester) async {
      final fakes = installCoverCaptureFakes();
      await openField(
        tester,
        fakes,
        <String?>[],
        settings: FakeAppSettingsOpener(),
      );
      await tester.tap(find.text('Add cover'));
      await tester.pump();
      await fakes.pickerGate.entered;

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      fakes.pickerGate.fail(PlatformException(code: 'camera_access_denied'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.takeException(), isNull);
      expect(find.text(scanCameraRefusedSentence), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a phone without a camera: the sentence says so', (
      tester,
    ) async {
      final fakes = installCoverCaptureFakes();
      await openField(
        tester,
        fakes,
        <String?>[],
        settings: FakeAppSettingsOpener(),
      );

      await captureFailing(
        tester,
        fakes,
        PlatformException(code: 'no_available_camera'),
      );

      expect(find.text(scanNoCameraSentence), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('anything else keeps "Could not capture a photo."', (
      tester,
    ) async {
      final fakes = installCoverCaptureFakes();
      await openField(
        tester,
        fakes,
        <String?>[],
        settings: FakeAppSettingsOpener(),
      );

      await captureFailing(
        tester,
        fakes,
        PlatformException(code: 'already_active', message: 'secret detail'),
      );

      expect(find.text(coverCaptureFailedSentence), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('popping while the picker is pending stops before crop and a '
      'disposed provider read', (tester) async {
    final fakes = installCoverCaptureFakes();
    final changes = <String?>[];
    final busyChanges = <bool>[];
    await openField(tester, fakes, changes, busyChanges: busyChanges);
    await tester.tap(find.text('Add cover'));
    await tester.pump();
    await fakes.pickerGate.entered;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    fakes
      ..finishCropper()
      ..finishPicker();
    await tester.pump();
    await tester.pump();

    expect(fakes.cropper.calls, 0);
    expect(fakes.controller.calls, 0);
    expect(changes, isEmpty);
    expect(busyChanges, [true], reason: 'no late busy callback after disposal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('popping while storage is pending drops the late result', (
    tester,
  ) async {
    final fakes = installCoverCaptureFakes();
    final changes = <String?>[];
    final busyChanges = <bool>[];
    await openField(tester, fakes, changes, busyChanges: busyChanges);
    await tester.tap(find.text('Add cover'));
    await tester.pump();
    await fakes.pickerGate.entered;
    fakes.finishPicker();
    await tester.pump();
    await fakes.cropperGate.entered;
    fakes.finishCropper();
    await tester.pump();
    await fakes.storeGate.entered;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    fakes.finishStore('covers/late.jpg');
    await tester.pumpAndSettle();

    expect(fakes.controller.calls, 1);
    expect(changes, isEmpty);
    expect(busyChanges, [true], reason: 'no late busy callback after disposal');
    expect(tester.takeException(), isNull);
  });
}
