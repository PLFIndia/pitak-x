import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/camera_failures.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';

/// Review finding P4-M8: the words a scan page and the cover camera show
/// when there is no camera picture (decisions D133, D134 and D135).
///
/// The words were chosen by the maintainer, word for word. This test holds
/// them, so that a change of one is a decision and not a slip. The widget
/// tests take the words from the same constants and so do not notice a
/// changed word; this file does.
void main() {
  test('the sentences of a scan page (D133)', () {
    expect(
      scanCameraRefusedSentence,
      'Pitak is not allowed to use the camera.',
    );
    expect(
      scanCameraRefusedHint,
      "Allow the camera in the phone's settings to scan.",
    );
    expect(scanNoCameraSentence, 'This phone has no camera.');
    expect(scanCameraDidNotStartSentence, 'The camera did not start.');
  });

  test('the buttons of a scan page (D133)', () {
    expect(openSettingsLabel, 'Open settings');
    expect(enterByHandLabel, 'Enter it by hand');
    expect(tryAgainLabel, 'Try again');
  });

  test('the words of the light button, for a screen reader (D135)', () {
    expect(turnOnLightLabel, 'Turn on the light');
    expect(turnOffLightLabel, 'Turn off the light');
  });

  test('each reason has its sentence on a scan page', () {
    expect(
      scanCameraSentenceFor(ScanCameraFailure.refused),
      scanCameraRefusedSentence,
    );
    expect(
      scanCameraSentenceFor(ScanCameraFailure.noCamera),
      scanNoCameraSentence,
    );
    expect(
      scanCameraSentenceFor(ScanCameraFailure.didNotStart),
      scanCameraDidNotStartSentence,
    );
  });

  test('only a refused camera has a second sentence that says what to do', () {
    expect(scanCameraHintFor(ScanCameraFailure.refused), scanCameraRefusedHint);
    expect(scanCameraHintFor(ScanCameraFailure.noCamera), isNull);
    expect(scanCameraHintFor(ScanCameraFailure.didNotStart), isNull);
  });

  test('the sentences of the cover camera (D134)', () {
    expect(
      coverCameraSentenceFor(CoverCameraFailure.refused),
      'Pitak is not allowed to use the camera.',
    );
    expect(
      coverCameraSentenceFor(CoverCameraFailure.noCamera),
      'This phone has no camera.',
    );
    expect(
      coverCameraSentenceFor(CoverCameraFailure.other),
      'Could not capture a photo.',
    );
  });

  test('a scan page and the cover camera say the same thing in the same '
      'words', () {
    expect(
      coverCameraSentenceFor(CoverCameraFailure.refused),
      scanCameraSentenceFor(ScanCameraFailure.refused),
    );
    expect(
      coverCameraSentenceFor(CoverCameraFailure.noCamera),
      scanCameraSentenceFor(ScanCameraFailure.noCamera),
    );
  });

  test('no sentence carries a text that came from a plugin', () {
    // Every sentence is one of the constants: nothing is put together at
    // run time (AGENTS.md §5: never show raw exception text).
    final all = <String>{
      for (final failure in ScanCameraFailure.values) ...[
        scanCameraSentenceFor(failure),
        ?scanCameraHintFor(failure),
      ],
      for (final failure in CoverCameraFailure.values)
        coverCameraSentenceFor(failure),
    };
    expect(all, {
      scanCameraRefusedSentence,
      scanCameraRefusedHint,
      scanNoCameraSentence,
      scanCameraDidNotStartSentence,
      coverCaptureFailedSentence,
    });
  });
}
