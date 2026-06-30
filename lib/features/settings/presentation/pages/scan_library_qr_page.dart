/// Library-pairing QR scanner (presentation, PLAN-merge.md D40). CAMERA,
/// just-in-time.
///
/// Opens the camera, watches for a QR carrying a Pitak library-ID payload
/// (`pitaka-lib:<id>`), and pops the VALIDATED library ID back to the caller so
/// it can be adopted. Only QR codes that pass [LibraryQrPayload.parse] (correct
/// prefix + well-formed ID) are accepted — an arbitrary QR the camera sees is
/// ignored. We only read codes; no frames are stored or transmitted
/// (§2a — in-person pairing, no network). Backed by flutter_zxing (zxing-cpp,
/// FOSS — no MLKit).
library;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';

/// Full-screen QR scanner. Pops a validated library ID string on success.
class ScanLibraryQrPage extends StatefulWidget {
  /// Creates the QR scan page.
  const ScanLibraryQrPage({super.key});

  @override
  State<ScanLibraryQrPage> createState() => _ScanLibraryQrPageState();
}

class _ScanLibraryQrPageState extends State<ScanLibraryQrPage> {
  bool _handled = false;

  void _onScan(Code code) {
    if (_handled) return;
    final raw = code.text;
    if (raw == null || !code.isValid) return;
    final id = LibraryQrPayload.parse(raw);
    if (id != null) {
      _handled = true;
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a library QR')),
      body: ReaderWidget(
        codeFormat: Format.qrCode,
        onScan: _onScan,
        showGallery: false,
        scanDelaySuccess: const Duration(milliseconds: 500),
      ),
    );
  }
}
