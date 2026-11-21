/// Barcode scanner screen (presentation, #29). CAMERA, just-in-time.
///
/// Opens the camera, watches for an EAN-13/ISBN barcode, and pops the first
/// structurally valid ISBN back to the caller (the add-book ISBN field). The
/// camera permission is requested by the scanner when the view starts; the
/// user can decline and back out. We only read barcodes — no frames are stored
/// or transmitted.
///
/// The camera itself is the shared [CameraScanView] (review finding P4-M8):
/// it owns the scanner package, and it says so when there is no camera
/// picture (refused, no camera, did not start). In those states this page
/// also offers "Enter it by hand", because an ISBN can be typed.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/camera_scan_view.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';

/// Replaces the camera widget in tests, using the same injectable-seam style
/// as `QrScanPage.buildScanner`. Production leaves it null.
typedef IsbnScannerBuilder = Widget Function(void Function(String raw) onText);

/// Full-screen barcode scanner. Pops a normalised ISBN string on success.
class ScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  ///
  /// [afterEnterByHand] is what the caller wants done once "Enter it by
  /// hand" has closed this page (decision D132). A form passes nothing: its
  /// ISBN field is on the page underneath. The Library screen, which has no
  /// field underneath, opens its "Add to library" sheet. Passed in by the
  /// caller so that this page knows no page of another feature.
  const ScannerPage({this.buildScanner, this.afterEnterByHand, super.key});

  /// Optional camera replacement used by widget tests.
  final IsbnScannerBuilder? buildScanner;

  /// Runs after "Enter it by hand" closed this page. Null: closing is all.
  final VoidCallback? afterEnterByHand;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _handled = false;

  void _onRaw(String raw) {
    if (_handled) return;
    final normalized = IsbnFormat.normalize(raw);
    if (IsbnFormat.isValid(normalized)) {
      _handled = true;
      Navigator.of(context).pop(normalized);
    }
  }

  /// "Enter it by hand": closes the page WITHOUT a value, exactly as Back
  /// does (fail closed: a page without a camera picture never hands a code
  /// to its caller), then lets the caller lead on.
  void _enterByHand() {
    // Taken before the pop: afterwards this page is on its way out.
    final after = widget.afterEnterByHand;
    Navigator.of(context).pop();
    after?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = widget.buildScanner;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ISBN barcode')),
      body: scanner != null
          ? scanner(_onRaw)
          : CameraScanView(
              codes: CameraScanCodes.isbnBarcode,
              onText: _onRaw,
              onEnterByHand: _enterByHand,
            ),
    );
  }
}
