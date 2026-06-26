/// Library-pairing QR scanner (presentation, PLAN-merge.md D40). CAMERA,
/// just-in-time.
///
/// Opens the camera, watches for a QR carrying a Pitak library-ID payload
/// (`pitaka-lib:<id>`), and pops the VALIDATED library ID back to the caller so
/// it can be adopted. Only QR codes that pass [LibraryQrPayload.parse] (correct
/// prefix + well-formed ID) are accepted — an arbitrary QR the camera sees is
/// ignored. We only read codes; no frames are stored or transmitted
/// (§2a — in-person pairing, no network).
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';

/// Full-screen QR scanner. Pops a validated library ID string on success.
class ScanLibraryQrPage extends StatefulWidget {
  /// Creates the QR scan page.
  const ScanLibraryQrPage({super.key});

  @override
  State<ScanLibraryQrPage> createState() => _ScanLibraryQrPageState();
}

class _ScanLibraryQrPageState extends State<ScanLibraryQrPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
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
      final id = LibraryQrPayload.parse(raw);
      if (id != null) {
        _handled = true;
        Navigator.of(context).pop(id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a library QR')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Text(
              'Point the camera at the other device\u2019s library QR code.',
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
