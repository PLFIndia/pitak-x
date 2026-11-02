/// Local cover-file reader for publishing (infrastructure, AGENTS.md §3.1).
///
/// Review finding N14 (layer rules not enforced): this file IO used to live
/// in the application
/// publish controller (`dart:io` in the application layer). It is
/// infrastructure now and reaches the controller as an injected function —
/// the same port style as the remote-cover fetcher.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

/// Reads + downscales a local cover for publishing, rooted at [coversDir].
///
/// Returns the cover's bytes re-encoded with the publish rendition
/// (`PublishCoverRendition` 1: 400x600 q80, metadata stripped — the
/// `ImageDownscaler` defaults, pinned to the rendition by
/// `publish_cover_rendition_test.dart`, ADR 0020 Decision 3), or null when
/// the reference is not a safe local cover, the file is missing, or the
/// re-encode fails.
///
/// Downscale-before-publish keeps the git push small AND strips EXIF/GPS
/// before anything reaches the public site. NO raw fallback — when the
/// re-encode fails (undecodable, or over the source dimension cap) the cover
/// is DROPPED, never published unstripped (REVIEW_FINDINGS_2 S11: a raw-bytes
/// fallback would silently ship the photographer's embedded GPS coordinates).
Future<List<int>?> Function(String coverUrl) localCoverReader(
  String coversDir,
) => (String src) async {
  final leaf = CoverPaths.leafOf(src);
  if (leaf == null) return null;
  final file = File(p.join(coversDir, leaf));
  if (!file.existsSync()) return null;
  try {
    // Worker isolate (N10-a): a publish may still re-encode many covers (the
    // first one after an update, a move), so the UI must never stall on it.
    return await ImageDownscaler.downscaleJpegAsync(await file.readAsBytes());
  } on Exception {
    return null;
  }
};
