/// The camera of a scan page: the one widget that reads codes with the
/// camera, and that says so when it cannot (core widget; review finding
/// P4-M8, ADR 0030).
///
/// Why one shared widget (beginner note): the app has two scan pages (ISBN
/// barcodes, QR codes). Each built the scanner package's widget itself, and
/// neither listened for "the camera could not start". A refused camera, or
/// a phone without one, left the page empty for good, without a word. Here
/// the listening exists once, and a test
/// (`test/architecture/camera_scanner_gate_test.dart`) keeps every other
/// file from building the package's widget, so that it cannot be forgotten
/// a third time. It also means an update of the scanner package touches
/// this one file.
///
/// The states, in the order a scan goes through them:
///  1. ASKING. The app asks the phone which cameras it has
///     (`device_cameras.dart`). The scanner package would show an empty
///     page on a phone without a camera and report nothing.
///  2. READING. The package's widget is on the screen and owns the camera.
///     It asks for the camera permission itself, the first time.
///  3. FAILED, with a reason: the camera is refused, the phone has no
///     camera, or the camera did not start. The camera area is replaced by
///     a sentence and the buttons that fit the reason.
///
/// Three things the package does not do by itself, so this widget does:
///  - it never tries again after a failed start. "Try again", and the
///    return from the phone's settings, build its widget anew;
///  - it has no words for a screen reader on its light button, and a
///    switch-camera button that has no use for reading a code. The first
///    gets words, the second is switched off;
///  - it draws its light button at the moment of the tap, before the phone
///    has switched the light, and never again: icon and words would be one
///    tap behind. This widget watches the camera and has the package's
///    widget built again when the camera's state has changed (D140).
///
/// Known limit: when the package's own decoding worker fails to start, the
/// package still reports nothing, and the page stays as it was before this
/// widget existed.
///
/// Fail closed: no failure ever hands a code to the page. Privacy: frames
/// are read and dropped as before; nothing a plugin reports is shown, and
/// a debug build logs an error's code at most.
library;

import 'dart:async';

import 'package:camera/camera.dart' show CameraController, CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/core/platform/camera_failures.dart';
import 'package:pitaka/core/platform/device_cameras.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';

/// Which codes a scan page reads. Each kind carries the scanner's settings
/// that were found to work for it (see `_tuningFor`).
enum CameraScanCodes {
  /// The barcode on the back of a book: EAN-13, with EAN-8 as a fallback.
  isbnBarcode,

  /// A QR code (a library's pairing code, a library card).
  qrCode,
}

/// Builds the widget that owns the camera. It is handed two callbacks:
/// [onText] for every valid code it reads, and [onCameraResult] with `null`
/// once the camera has started, or with what the camera plugin threw.
///
/// A test seam: production leaves it out and gets the scanner package's
/// widget.
typedef CameraReaderBuilder =
    Widget Function(
      void Function(String raw) onText,
      void Function(Exception? error) onCameraResult,
    );

/// The camera area of a scan page. See the file header.
class CameraScanView extends ConsumerStatefulWidget {
  /// Creates the view.
  ///
  /// [onText] is called with the text of every valid code the camera reads;
  /// what a text means is the page's business. [onEnterByHand], when given,
  /// adds the button "Enter it by hand" to every failed state; the view
  /// only tells the page, it never closes it.
  const CameraScanView({
    required this.codes,
    required this.onText,
    this.onEnterByHand,
    this.buildReader,
    super.key,
  });

  /// Which codes to read.
  final CameraScanCodes codes;

  /// Called with the text of every valid code that is read.
  final void Function(String raw) onText;

  /// What "Enter it by hand" does. Null: the button is not shown (a QR
  /// code cannot be typed).
  final VoidCallback? onEnterByHand;

  /// Test seam: replaces the scanner package's widget.
  final CameraReaderBuilder? buildReader;

  @override
  ConsumerState<CameraScanView> createState() => _CameraScanViewState();
}

/// Where a scan stands. Sealed, so that `build` handles every case.
sealed class _Phase {
  const _Phase();
}

final class _Asking extends _Phase {
  const _Asking();
}

final class _Reading extends _Phase {
  const _Reading();
}

final class _Failed extends _Phase {
  const _Failed(this.failure);

  final ScanCameraFailure failure;
}

class _CameraScanViewState extends ConsumerState<CameraScanView>
    with WidgetsBindingObserver {
  _Phase _phase = const _Asking();

  /// Counts the starts of the camera. A callback that belongs to an earlier
  /// start is dropped: the scanner package can call back after its widget
  /// was thrown away.
  int _start = 0;

  /// True from the tap on "Open settings" until the app is in front again.
  ///
  /// Why a memory and not "try again at every return" (beginner note):
  /// Android's own permission dialog also sends the app away and brings it
  /// back. A page that started the camera at every return would ask again
  /// the moment the user said "Don't allow", in a loop.
  bool _sentToSettings = false;

  /// The camera the scanner package runs now, as the package handed it
  /// over; null while there is none. Watched for one reason: see
  /// [_onCameraChanged].
  CameraController? _camera;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_begin());
  }

  @override
  void dispose() {
    // The package lets go of its camera a moment AFTER this page is gone,
    // and the camera reports that too.
    _camera?.removeListener(_onCameraChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Watches [camera] in the place of the one watched so far. The package
  /// makes a new one at every start, also after the app was in the
  /// background.
  void _watch(CameraController? camera) {
    _camera?.removeListener(_onCameraChanged);
    _camera = camera;
    camera?.addListener(_onCameraChanged);
  }

  /// The camera's state has changed: the package's widget is built again.
  ///
  /// Why (beginner note, decision D140): the package's light button asks
  /// the camera to switch the light and draws itself again in the same
  /// moment. The camera records its new state only when the phone has
  /// answered, some frames later, and nothing draws the button after that.
  /// So icon and words showed the state the light had just LEFT: "Turn on
  /// the light" while it was on. Building the package's widget again once
  /// the camera has really changed puts both right.
  void _onCameraChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_sentToSettings) return;
    // Back from the phone's settings: try the camera again, once. The
    // scanner package would not (it gives up after a failed start).
    _sentToSettings = false;
    unawaited(_begin());
  }

  /// Starts a scan from its first state: asks the phone for its cameras,
  /// then shows the scanner or a sentence.
  Future<void> _begin() async {
    // A new start: whatever an earlier scanner still reports is dropped.
    _start++;
    if (_phase is! _Asking) setState(() => _phase = const _Asking());
    DeviceCameraAnswer answer;
    try {
      answer = await ref.read(deviceCamerasProvider).ask();
    } on Object {
      // The port promises to answer instead of failing. Should one ever
      // break that promise, the page must still not stay empty without a
      // word: that is the fault this widget exists to remove.
      answer = DeviceCameraAnswer.unreadable;
    }
    if (!mounted) return;
    setState(() {
      _phase = switch (answer) {
        DeviceCameraAnswer.hasCamera => const _Reading(),
        DeviceCameraAnswer.noCamera => const _Failed(
          ScanCameraFailure.noCamera,
        ),
        DeviceCameraAnswer.unreadable => const _Failed(
          ScanCameraFailure.didNotStart,
        ),
      };
    });
  }

  /// True while the scanner of the start numbered [start] is on the screen.
  bool _isCurrentReader(int start) =>
      mounted && start == _start && _phase is _Reading;

  void _onText(int start, String raw) {
    if (!_isCurrentReader(start)) return;
    widget.onText(raw);
  }

  /// What the scanner of the start numbered [start] reports: the [camera]
  /// it runs now (null when it has none), or the [error] its start ended
  /// with.
  void _onCameraResult(int start, CameraController? camera, Exception? error) {
    if (!_isCurrentReader(start)) return;
    _watch(camera);
    // No error means the camera started: the scanner stays as it is.
    if (error == null) return;
    // Only the CODE of the camera plugin's own error is read. The text of
    // an exception is never shown and never logged (AGENTS.md §5, §6.2).
    final code = error is CameraException ? error.code : null;
    appLog(
      code == null
          ? 'camera_scan: camera failed'
          : 'camera_scan: camera failed: $code',
    );
    setState(() => _phase = _Failed(scanCameraFailureFor(code)));
  }

  Future<void> _openSettings() async {
    // A second tap while the settings are on their way changes nothing.
    if (_sentToSettings) return;
    // Remembered BEFORE the call: the app leaves the front while the call
    // is still out.
    _sentToSettings = true;
    final opened = await ref.read(appSettingsOpenerProvider).open();
    // Not opened: the page keeps its sentence, which says where the camera
    // can be allowed, and no return is waited for.
    if (!opened) _sentToSettings = false;
  }

  Widget _reader() {
    final start = _start;
    void onText(String raw) => _onText(start, raw);
    final buildReader = widget.buildReader;
    return buildReader != null
        // A stand-in has no camera to hand over.
        ? buildReader(onText, (error) => _onCameraResult(start, null, error))
        : _packageReader(
            widget.codes,
            onText,
            (camera, error) => _onCameraResult(start, camera, error),
          );
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Asking():
        // A moment only. A busy sign for it is not part of this widget.
        return const SizedBox.expand();
      case _Reading():
        return _reader();
      case _Failed(:final failure):
        final refused = failure == ScanCameraFailure.refused;
        final canOpenSettings =
            refused && ref.watch(appSettingsOpenerProvider).isAvailable;
        return _CameraFailureMessage(
          failure: failure,
          // No "Try again" for a refused camera: after the second refusal
          // Android shows no dialog any more, and the app cannot tell the
          // first refusal from the second (decision D133).
          onOpenSettings: canOpenSettings
              ? () => unawaited(_openSettings())
              : null,
          onTryAgain: failure == ScanCameraFailure.didNotStart
              ? () => unawaited(_begin())
              : null,
          onEnterByHand: widget.onEnterByHand,
        );
    }
  }
}

/// The sentence(s) and the buttons that stand in the place of the camera.
class _CameraFailureMessage extends StatelessWidget {
  const _CameraFailureMessage({
    required this.failure,
    required this.onOpenSettings,
    required this.onTryAgain,
    required this.onEnterByHand,
  });

  final ScanCameraFailure failure;

  /// Each button is built only when its callback is given.
  final VoidCallback? onOpenSettings;
  final VoidCallback? onTryAgain;
  final VoidCallback? onEnterByHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = scanCameraHintFor(failure);
    final onOpenSettings = this.onOpenSettings;
    final onTryAgain = this.onTryAgain;
    final onEnterByHand = this.onEnterByHand;
    final hasButton =
        onOpenSettings != null || onTryAgain != null || onEnterByHand != null;
    // Centred, and scrolling when the screen is small or the text large.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // One live region that holds both sentences: a screen reader
            // reads them out when they take the place of the camera.
            Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    scanCameraSentenceFor(failure),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasButton) const SizedBox(height: 20),
            // One button under the other: each keeps its words whole on a
            // narrow screen with large text.
            if (onOpenSettings != null)
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text(openSettingsLabel),
              ),
            if (onTryAgain != null)
              FilledButton(
                onPressed: onTryAgain,
                child: const Text(tryAgainLabel),
              ),
            if (onEnterByHand != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onEnterByHand,
                child: const Text(enterByHandLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The scanner's settings for one kind of code.
typedef _Tuning = ({
  int codeFormat,
  double cropPercent,
  bool thorough,
  Duration scanDelay,
});

/// Detection tuning per kind of code.
///
/// ISBN barcodes: flutter_zxing decodes only a centred SQUARE crop of the
/// camera frame (side = min(w,h) * cropPercent; default 0.5). An EAN-13
/// book barcode is wide and short, so at the default it must be framed
/// almost perfectly to land inside the crop; on-device this made detection
/// rare (Pixel 8a, 2026-07-09). The crop is widened to 90% and zxing-cpp's
/// robustness passes are switched on (tryHarder = slower but thorough scan,
/// tryInverted = light-on-dark barcodes, tryDownscale = extra pyramid pass
/// for blurry/high-res frames). A 300 ms retry cadence (default 1000 ms)
/// makes the scanner feel responsive. Mirrors the upstream guidance in
/// khoren93/flutter_zxing issues #185/#197.
///
/// QR codes: the package's own defaults, written out so that an update of
/// the package cannot change them unseen.
_Tuning _tuningFor(CameraScanCodes codes) => switch (codes) {
  CameraScanCodes.isbnBarcode => (
    codeFormat: Format.ean13 | Format.ean8,
    cropPercent: 0.9,
    thorough: true,
    scanDelay: const Duration(milliseconds: 300),
  ),
  CameraScanCodes.qrCode => (
    codeFormat: Format.qrCode,
    cropPercent: 0.5,
    thorough: false,
    scanDelay: const Duration(milliseconds: 1000),
  ),
};

/// The production scanner: flutter_zxing's camera reader (zxing-cpp, FOSS,
/// no MLKit). The ONLY place in the app that builds it.
Widget _packageReader(
  CameraScanCodes codes,
  void Function(String raw) onText,
  void Function(CameraController? camera, Exception? error) onCameraResult,
) {
  final tuning = _tuningFor(codes);
  return ReaderWidget(
    codeFormat: tuning.codeFormat,
    // Only VALID decoded text is handed on.
    onScan: (code) {
      final raw = code.text;
      if (raw == null || !code.isValid) return;
      onText(raw);
    },
    // The one way the package reports a camera that could not start (it
    // was not passed before review finding P4-M8), and the way it hands
    // over the camera it runs.
    onControllerCreated: onCameraResult,
    showGallery: false,
    // No use for reading a code, and it had no words for a screen reader.
    showToggleCamera: false,
    // The light button shows an icon only. The package picks the icon by
    // the camera's flash mode; a tap switches the light off from "torch"
    // and on from every other mode, and the words say what a tap does.
    // (They are right only because this widget has the button built again
    // once the light has changed: see `_onCameraChanged`.)
    flashOnIcon: const Icon(Icons.flash_on, semanticLabel: turnOffLightLabel),
    flashOffIcon: const Icon(Icons.flash_off, semanticLabel: turnOnLightLabel),
    flashAutoIcon: const Icon(
      Icons.flash_auto,
      semanticLabel: turnOnLightLabel,
    ),
    flashAlwaysIcon: const Icon(
      Icons.flash_on,
      semanticLabel: turnOnLightLabel,
    ),
    scanDelaySuccess: const Duration(milliseconds: 500),
    cropPercent: tuning.cropPercent,
    tryHarder: tuning.thorough,
    tryInverted: tuning.thorough,
    tryDownscale: tuning.thorough,
    scanDelay: tuning.scanDelay,
  );
}
