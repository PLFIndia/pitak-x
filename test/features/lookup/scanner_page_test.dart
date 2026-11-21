import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_cameras.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';

import '../../support/fake_scan_camera.dart';

/// Review finding P4-M8: the ISBN scan page when it has no camera picture
/// (decisions D130, D132 and D133).
///
/// The page shows its camera through the shared `CameraScanView`, whose
/// states are tested in `test/core/widgets/camera_scan_view_test.dart`.
/// These tests hold what is the PAGE's own: that it uses that view at all,
/// that it offers "Enter it by hand" (a QR scan page does not), and that
/// this button closes the page without a value, as Back does.
///
/// The camera is played by the phone's list of cameras: an empty list, or
/// one that cannot be read, is a failed state that needs no camera plugin.
void main() {
  const notClosed = 'NOT_CLOSED';

  late FakeDeviceCameras cameras;
  late String? closedWith;

  setUp(() {
    cameras = FakeDeviceCameras(answer: DeviceCameraAnswer.noCamera);
    closedWith = notClosed;
  });

  /// Opens [page] over a first page, as the app does, and keeps what the
  /// scan page is closed with.
  Future<void> openScanner(WidgetTester tester, ScannerPage page) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceCamerasProvider.overrideWithValue(cameras),
          appSettingsOpenerProvider.overrideWithValue(FakeAppSettingsOpener()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  closedWith = await Navigator.of(
                    context,
                  ).push<String>(MaterialPageRoute(builder: (_) => page));
                },
                child: const Text('open-scanner'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Scan ISBN barcode'), findsOneWidget);
  }

  testWidgets('a phone without a camera: the page says so and offers '
      '"Enter it by hand"', (tester) async {
    await openScanner(tester, const ScannerPage());

    expect(find.text(scanNoCameraSentence), findsOneWidget);
    expect(find.text(enterByHandLabel), findsOneWidget);
    expect(closedWith, notClosed);
  });

  testWidgets('a list of cameras that cannot be read: "The camera did not '
      'start.", "Try again" and "Enter it by hand"', (tester) async {
    cameras.answer = DeviceCameraAnswer.unreadable;
    await openScanner(tester, const ScannerPage());

    expect(find.text(scanCameraDidNotStartSentence), findsOneWidget);
    expect(find.text(tryAgainLabel), findsOneWidget);
    expect(find.text(enterByHandLabel), findsOneWidget);
  });

  testWidgets('"Enter it by hand" closes the page without a value, as Back '
      'does', (tester) async {
    await openScanner(tester, const ScannerPage());

    await tester.tap(find.text(enterByHandLabel));
    await tester.pumpAndSettle();

    expect(find.text('Scan ISBN barcode'), findsNothing);
    // Fail closed: a failed state never hands a code to the form.
    expect(closedWith, isNull);
  });

  testWidgets('what the caller wants done afterwards runs once, when the '
      'page is closed', (tester) async {
    final seen = <String>[];
    await openScanner(
      tester,
      ScannerPage(
        // What is on the screen at the moment the caller is told.
        afterEnterByHand: () => seen.add('told, closed with: $closedWith'),
      ),
    );

    await tester.tap(find.text(enterByHandLabel));
    // Told at the tap, in the same turn as the page is closed: the caller
    // may open its own sheet at once.
    expect(seen, hasLength(1));
    await tester.pumpAndSettle();

    expect(seen, hasLength(1));
    expect(find.text('Scan ISBN barcode'), findsNothing);
    expect(closedWith, isNull);
  });

  testWidgets('a second tap on "Enter it by hand" closes nothing more', (
    tester,
  ) async {
    var told = 0;
    await openScanner(tester, ScannerPage(afterEnterByHand: () => told++));

    // No frame between the two taps: the button is still on the screen.
    // (The page needs no guard of its own for this: a navigator takes no
    // tap between a pop and the next frame. Tried by hand on 2026-11-21.)
    await tester.tap(find.text(enterByHandLabel));
    await tester.tap(find.text(enterByHandLabel), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(told, 1);
    // The page underneath is still there: only the scan page was closed.
    expect(find.text('open-scanner'), findsOneWidget);
  });

  testWidgets('a second code that arrives while the page closes is not '
      'handed on', (tester) async {
    // The camera can read the same barcode twice before the page is gone.
    late void Function(String raw) emit;
    await openScanner(
      tester,
      ScannerPage(
        buildScanner: (onText) {
          emit = onText;
          return const SizedBox();
        },
      ),
    );

    emit('9780306406157');
    emit('9780140449136');
    await tester.pumpAndSettle();

    // The first valid ISBN closes the page; the second changes nothing.
    expect(closedWith, '9780306406157');
    expect(find.text('open-scanner'), findsOneWidget);
  });
}
