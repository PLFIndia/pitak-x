/// A self-contained QR-code widget (presentation, PLAN-merge.md D40).
///
/// Paints a QR matrix with a [CustomPainter] using the `qr` package's pure
/// encoder (already in the dependency tree via `pdf`/`barcode`). No camera, no
/// network, no platform views — just a black-on-white drawing. Used to display
/// this device's library-pairing payload for another maintainer to scan.
///
/// Error-correction level M mirrors the Kotlin app's `QrEncoder` so both apps
/// produce equivalent codes for the same payload.
library;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Renders [data] as a square QR code of side [size].
class QrView extends StatelessWidget {
  /// Creates a QR view for [data].
  const QrView({required this.data, this.size = 220, super.key});

  /// The exact string encoded into the QR (e.g. `pitaka-lib:<id>`).
  final String data;

  /// Square side length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Encoding can throw only if the payload is too long for the format — a
    // library payload never is, but fail safe to an empty box not a crash.
    QrImage? image;
    try {
      image = QrImage(
        QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
    } on Object {
      image = null;
    }

    return Container(
      width: size,
      height: size,
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: image == null
          ? const SizedBox.shrink()
          : CustomPaint(painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    if (count == 0) return;
    final cell = size.width / count;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          // +0.5 overdraw avoids hairline gaps between modules at fraction px.
          canvas.drawRect(
            Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
