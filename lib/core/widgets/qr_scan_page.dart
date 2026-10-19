/// Generic QR-scan page (core widget; docs/ARCHITECTURE.md §3).
///
/// Replaces the settings-specific `ScanLibraryQrPage`: every scan flow in the
/// app (pairing with a maintainer, a hub adding a member by library card)
/// needs the SAME camera plumbing with a DIFFERENT payload rule, so the rule
/// is injected as [QrScanPage.accept] instead of hard-wired. Backed by
/// flutter_zxing (zxing-cpp, FOSS — no MLKit); we only read codes, no frames
/// are stored or transmitted.
///
/// The decision logic ([QrScanPage.decide]) is a pure static so the "which
/// payloads does this screen take, and what does it say to the others" policy
/// is unit-testable WITHOUT a camera — the repo's rule for scanner tests
/// (see `test/features/library/scan_routing_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// What one scanned payload means for a [QrScanPage]. Sealed so the widget
/// (and the tests) handle every case explicitly (AGENTS.md §5 style).
sealed class ScanOutcome<T> {
  const ScanOutcome();
}

/// The payload passed [QrScanPage.accept] — the page pops with [value].
final class ScanAccepted<T> extends ScanOutcome<T> {
  /// Creates an acceptance carrying the parsed [value].
  const ScanAccepted(this.value);

  /// The validated payload the caller asked for.
  final T value;
}

/// The payload is NOT ours, but a known-other Pitak payload (e.g. a pairing
/// code on the add-member screen): show [hint] once, keep scanning.
final class ScanRejected<T> extends ScanOutcome<T> {
  /// Creates a rejection that should surface [hint].
  const ScanRejected(this.hint);

  /// Plain-words message telling the user what they scanned instead.
  final String hint;
}

/// Not a payload this page understands at all: ignore silently, keep scanning.
final class ScanIgnored<T> extends ScanOutcome<T> {
  /// Creates a silent ignore.
  const ScanIgnored();
}

/// Full-screen QR scanner. Pops the validated payload `T` on success, or null
/// when the user backs out.
class QrScanPage<T> extends StatefulWidget {
  /// Creates a scan page.
  ///
  /// [accept] is the payload rule: parse a raw string into `T`, or null when
  /// the code is not one this screen takes. [rejectedHint] +
  /// [isKnownOtherPayload]
  /// optionally name a KNOWN-other Pitak payload so the user gets a helpful
  /// message instead of silence (D2: the add-member screen must say "that is a
  /// pairing code" rather than just ignore it).
  ///
  /// [buildScanner] replaces the camera widget — a test seam, the same
  /// injectable-seam style as `BoundedHttpFetcher(client:)`. Production code
  /// leaves it null and gets the flutter_zxing [ReaderWidget].
  const QrScanPage({
    required this.title,
    required this.accept,
    this.rejectedHint,
    this.isKnownOtherPayload,
    this.buildScanner,
    super.key,
  });

  /// App-bar title telling the user what to point the camera at.
  final String title;

  /// Payload rule: validated [T] for an accepted code, null otherwise.
  final T? Function(String raw) accept;

  /// Message shown (once) when [isKnownOtherPayload] matches a scanned code.
  final String? rejectedHint;

  /// Detects a known-but-wrong Pitak payload (e.g. `pitaka-lib:` on the
  /// library-card screen) so the hint is shown for it only — arbitrary QRs
  /// the camera sees stay silently ignored.
  final bool Function(String raw)? isKnownOtherPayload;

  /// Test seam: builds the scanning surface, forwarding each decoded payload
  /// string to the given callback. Null → the real camera [ReaderWidget].
  final Widget Function(void Function(String raw) onText)? buildScanner;

  /// The pure scan decision: accept → pop value; known-other → hint; anything
  /// else → ignore. No camera, no widgets — unit-testable as-is.
  static ScanOutcome<T> decide<T>({
    required String raw,
    required T? Function(String raw) accept,
    String? rejectedHint,
    bool Function(String raw)? isKnownOtherPayload,
  }) {
    final value = accept(raw);
    if (value != null) return ScanAccepted<T>(value);
    if (rejectedHint != null && (isKnownOtherPayload?.call(raw) ?? false)) {
      return ScanRejected<T>(rejectedHint);
    }
    return ScanIgnored<T>();
  }

  @override
  State<QrScanPage<T>> createState() => _QrScanPageState<T>();
}

class _QrScanPageState<T> extends State<QrScanPage<T>> {
  /// Set once an accepted code popped the page, so a second camera callback
  /// racing the route animation cannot pop twice.
  bool _handled = false;

  /// Set once the known-other hint was shown, so holding a wrong code in
  /// front of the camera does not spam the same SnackBar every frame.
  bool _hintShown = false;

  void _onText(String raw) {
    if (_handled) return;
    switch (QrScanPage.decide<T>(
      raw: raw,
      accept: widget.accept,
      rejectedHint: widget.rejectedHint,
      isKnownOtherPayload: widget.isKnownOtherPayload,
    )) {
      case ScanAccepted<T>(:final value):
        _handled = true;
        Navigator.of(context).pop(value);
      case ScanRejected<T>(:final hint):
        if (_hintShown) return;
        _hintShown = true;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(hint)));
      case ScanIgnored<T>():
        break; // not ours: keep scanning, say nothing
    }
  }

  /// The production scanner: flutter_zxing's camera reader, restricted to QR
  /// codes, forwarding only VALID decoded text (mirrors the old
  /// `ScanLibraryQrPage` exactly).
  Widget _defaultScanner(void Function(String raw) onText) => ReaderWidget(
    codeFormat: Format.qrCode,
    onScan: (code) {
      final raw = code.text;
      if (raw == null || !code.isValid) return;
      onText(raw);
    },
    showGallery: false,
    scanDelaySuccess: const Duration(milliseconds: 500),
  );

  @override
  Widget build(BuildContext context) {
    final scanner = widget.buildScanner ?? _defaultScanner;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: scanner(_onText),
    );
  }
}
