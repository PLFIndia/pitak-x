/// Barcode scanner screen (presentation, #29). CAMERA, just-in-time.
///
/// Opens the camera, watches for an EAN-13/ISBN barcode, and pops the first
/// structurally valid ISBN back to the caller (the add-book ISBN field). The
/// camera permission is requested by the scanner when the view starts; the
/// user can decline and back out. We only read barcodes — no frames are stored
/// or transmitted. Backed by flutter_zxing (zxing-cpp, FOSS — no MLKit).
library;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';

/// Full-screen barcode scanner. Pops a normalised ISBN string on success.
class ScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _handled = false;

  void _onScan(Code code) {
    if (_handled) return;
    final raw = code.text;
    if (raw == null || !code.isValid) return;
    final normalized = IsbnFormat.normalize(raw);
    if (IsbnFormat.isValid(normalized)) {
      _handled = true;
      Navigator.of(context).pop(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ISBN barcode')),
      body: ReaderWidget(
        // ISBN barcodes are EAN-13 (with EAN-8 as a fallback).
        codeFormat: Format.ean13 | Format.ean8,
        onScan: _onScan,
        showGallery: false,
        scanDelaySuccess: const Duration(milliseconds: 500),
        // Detection tuning. flutter_zxing decodes only a centred SQUARE crop
        // of the camera frame (side = min(w,h) * cropPercent; default 0.5).
        // An EAN-13 book barcode is wide and short, so at the default it must
        // be framed almost perfectly to land inside the crop — on-device this
        // made detection rare (Pixel 8a, 2026-07-09). Widen the crop to 90%
        // and enable zxing-cpp's robustness passes (tryHarder = slower but
        // thorough scan, tryInverted = light-on-dark barcodes, tryDownscale =
        // extra pyramid pass for blurry/high-res frames). A 300ms retry cadence
        // (default 1000ms) makes the scanner feel responsive. Mirrors the
        // upstream guidance in khoren93/flutter_zxing issues #185/#197.
        cropPercent: 0.9,
        tryHarder: true,
        tryInverted: true,
        tryDownscale: true,
        scanDelay: const Duration(milliseconds: 300),
      ),
    );
  }
}
