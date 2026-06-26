/// Barcode scanner screen (presentation, #29). CAMERA, just-in-time.
///
/// Opens the camera, watches for an EAN-13/ISBN barcode, and pops the first
/// structurally valid ISBN back to the caller (the add-book ISBN field). The
/// camera permission is requested by mobile_scanner when the view starts; the
/// user can decline and back out. We only read barcodes — no frames are stored
/// or transmitted.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';

/// Full-screen barcode scanner. Pops a normalised ISBN string on success.
class ScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final normalized = IsbnFormat.normalize(raw);
      if (IsbnFormat.isValid(normalized)) {
        _handled = true;
        Navigator.of(context).pop(normalized);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ISBN barcode')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Simple aiming guide.
          IgnorePointer(
            child: Container(
              width: 260,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Text(
              'Point the camera at the book’s barcode.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
