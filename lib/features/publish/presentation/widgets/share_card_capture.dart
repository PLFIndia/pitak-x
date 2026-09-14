/// Rasterises an on-screen [RepaintBoundary] to PNG bytes (presentation).
///
/// Adapted from the `screenshot` package (SachinGanesh/screenshot, MIT):
/// `RenderRepaintBoundary.toImage(pixelRatio)` → `Image.toByteData(png)`.
/// Inlined (≈20 lines) rather than depended on — AGENTS.md §9: no new package
/// for a problem the framework already solves.
///
/// Why this works for a scaled preview: `toImage` renders the boundary's OWN
/// subtree at its OWN layout size (the 1050×600 card), ignoring any
/// `FittedBox`/`Transform` applied by ancestors. So the thumbnail the user
/// sees and the full-size PNG come from the same render tree.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show GlobalKey, RepaintBoundary;

/// Device-independent output scale: 1050×600 logical → 2100×1200 px, crisp
/// on any phone and small enough for chat apps (a few hundred KB).
const double kShareCardPixelRatio = 2;

/// Encodes the [RepaintBoundary] behind [boundaryKey] as a PNG.
///
/// Returns null when the boundary is not mounted or has not painted yet —
/// the caller shows a fixed "could not create the card" message (§5: no raw
/// exception text). Never throws for those expected states.
///
/// Call this BEFORE any `setState` in the same handler: the boundary must
/// already be painted (the user tapped a button inside the sheet, so it is),
/// and this function deliberately does not wait for a frame — under
/// `flutter_test` frames only advance through `pump()`, so an internal
/// `endOfFrame` await would deadlock every widget test that captures.
Future<Uint8List?> captureBoundaryPng(
  GlobalKey boundaryKey, {
  double pixelRatio = kShareCardPixelRatio,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return null;
  if (!renderObject.attached) return null;
  // `toImage` asserts (debug only) that the boundary has been painted.
  // `debugNeedsPaint` is gated on kDebugMode because its getter is only
  // initialised inside an assert and would throw in release.
  if (kDebugMode && renderObject.debugNeedsPaint) return null;
  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
