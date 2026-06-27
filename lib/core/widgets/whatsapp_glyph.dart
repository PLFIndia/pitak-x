/// A WhatsApp-style glyph (presentation util).
///
/// Drawn with a [CustomPainter] rather than shipping the WhatsApp brand logo:
/// it's the recognizable speech-bubble-with-handset shape (a generic
/// "message on a phone" mark), avoiding any trademarked asset. Sized + coloured
/// like a Material icon so it drops into an [IconButton].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A speech-bubble-with-phone-handset glyph, [size] square, in [color].
class WhatsappGlyph extends StatelessWidget {
  /// Creates the glyph. [color] defaults to the ambient [IconTheme] colour.
  const WhatsappGlyph({this.size = 24, this.color, super.key});

  /// Edge length in logical pixels.
  final double size;

  /// Glyph colour (falls back to the current icon colour).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).iconTheme.color ??
        Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _WhatsappPainter(resolved)),
    );
  }
}

class _WhatsappPainter extends CustomPainter {
  _WhatsappPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Speech bubble (circle) + a tail poking to the lower-left.
    final c = Offset(w * 0.5, w * 0.46);
    final r = w * 0.42;
    final bubble = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final tail = Path()
      ..moveTo(w * 0.18, w * 0.46)
      ..lineTo(w * 0.05, w * 0.95)
      ..lineTo(w * 0.48, w * 0.78)
      ..close();
    canvas.drawPath(Path.combine(PathOperation.union, bubble, tail), fill);

    // Handset, drawn in the bubble's contrasting tone so it reads on the disc.
    // We approximate "knockout" by painting it with a blend that darkens/
    // lightens against the fill; a simple inverted-alpha receiver works at
    // icon sizes, so paint it as a thick stroked diagonal with two end pads.
    final handset = Paint()
      ..color = _contrast(color)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.10
      ..isAntiAlias = true;

    final a = Offset(c.dx - w * 0.13, c.dy - w * 0.13);
    final b = Offset(c.dx + w * 0.13, c.dy + w * 0.13);
    canvas.drawLine(a, b, handset);
    // Two small pads (ear/mouth) at the ends for the handset silhouette.
    final padPaint = Paint()
      ..color = _contrast(color)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    _pad(canvas, a, w, padPaint, rotate: -math.pi / 4);
    _pad(canvas, b, w, padPaint, rotate: -math.pi / 4);
  }

  void _pad(
    Canvas canvas,
    Offset at,
    double w,
    Paint paint, {
    required double rotate,
  }) {
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(rotate);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.16, height: w * 0.26),
      Radius.circular(w * 0.08),
    );
    canvas
      ..drawRRect(rect, paint)
      ..restore();
  }

  /// A readable handset tone against [base]: white on a dark glyph, else a
  /// translucent dark. Keeps the receiver visible whatever the icon colour.
  Color _contrast(Color base) {
    final luminance = base.computeLuminance();
    return luminance < 0.5
        ? Colors.white
        : Colors.black.withValues(alpha: 0.85);
  }

  @override
  bool shouldRepaint(_WhatsappPainter old) => old.color != color;
}
