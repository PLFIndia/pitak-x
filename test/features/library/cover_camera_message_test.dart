import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/features/library/presentation/widgets/cover_camera_message.dart';

import '../../support/fake_scan_camera.dart';

/// Review finding P4-M8, decision D134: the bar the app shows when the
/// cover camera took no photo.
///
/// Before it, every failure got "Could not capture a photo.", a refused
/// camera too. These tests hold which sentence each failure gets, that
/// "Open settings" stands only beside a refused camera and only where the
/// settings can be opened, and that the bar with the button goes away by
/// itself (a bar that stayed would hold every later message of the app
/// back).
void main() {
  late FakeAppSettingsOpener settings;

  setUp(() => settings = FakeAppSettingsOpener());

  /// A page, over a first page, with one button that reports [error] as a
  /// failed cover photo.
  Future<void> pumpAndFail(WidgetTester tester, Object error) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appSettingsOpenerProvider.overrideWithValue(settings)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('A form')),
                      body: Consumer(
                        builder: (context, ref, _) => TextButton(
                          onPressed: () =>
                              showCoverCameraFailure(context, ref, error),
                          child: const Text('fail'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fail'));
    // The bar slides in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  PlatformException refused() => PlatformException(
    code: 'camera_access_denied',
    message: 'The user did not allow camera access.',
  );

  group('the camera is refused', () {
    testWidgets('the sentence, and "Open settings" in the bar', (tester) async {
      await pumpAndFail(tester, refused());

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, openSettingsLabel),
        findsOneWidget,
      );
      expect(find.text(coverCaptureFailedSentence), findsNothing);
      // Nothing is opened before the tap.
      expect(settings.openCalls, 0);
    });

    testWidgets('"Open settings" opens the settings, once', (tester) async {
      await pumpAndFail(tester, refused());

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();

      expect(settings.openCalls, 1);
    });

    testWidgets('where the settings cannot be opened: the sentence without '
        'the button', (tester) async {
      settings.isAvailable = false;
      await pumpAndFail(tester, refused());

      expect(find.text(scanCameraRefusedSentence), findsOneWidget);
      expect(find.text(openSettingsLabel), findsNothing);
      expect(find.byType(SnackBarAction), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the bar with the button goes away by itself after six '
        'seconds', (tester) async {
      await pumpAndFail(tester, refused());
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 6));
      expect(bar.persist, isFalse);

      // Still there shortly before the six seconds are over ...
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(scanCameraRefusedSentence), findsOneWidget);

      // ... and gone after them, without a tap.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(scanCameraRefusedSentence), findsNothing);
      expect(settings.openCalls, 0);
    });

    testWidgets('the button still works after the page was left', (
      tester,
    ) async {
      // The bar belongs to the app, not to the page that showed it.
      await pumpAndFail(tester, refused());

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('A form'), findsNothing);
      expect(find.text(openSettingsLabel), findsOneWidget);

      await tester.tap(find.text(openSettingsLabel));
      await tester.pumpAndSettle();

      expect(settings.openCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('a phone without a camera', () {
    testWidgets('the sentence, and no button', (tester) async {
      await pumpAndFail(tester, PlatformException(code: 'no_available_camera'));

      expect(find.text(scanNoCameraSentence), findsOneWidget);
      expect(find.byType(SnackBarAction), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('anything else', () {
    for (final (label, error) in <(String, Object)>[
      (
        'another code of the plugin',
        PlatformException(code: 'already_active', message: 'secret detail'),
      ),
      ('an exception without a code', Exception('secret detail')),
      (
        'an exception whose TEXT names a refusal',
        Exception('camera_access_denied'),
      ),
      ('a format error of the crop step', const FormatException('secret')),
    ]) {
      testWidgets('$label keeps "Could not capture a photo.", without a '
          'button and without its text', (tester) async {
        await pumpAndFail(tester, error);

        expect(find.text(coverCaptureFailedSentence), findsOneWidget);
        expect(find.byType(SnackBarAction), findsNothing);
        expect(find.textContaining('secret'), findsNothing);
        expect(find.textContaining('camera_access_denied'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('a bar without a button keeps the usual four seconds', (
      tester,
    ) async {
      await pumpAndFail(tester, Exception('x'));

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 4));
      expect(bar.action, isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
