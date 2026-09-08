/// Reads a user-picked file into memory WITHOUT trusting its size
/// (core/platform, AGENTS.md §3.1).
///
/// Single source of truth for "load the file the user just chose" (M05,
/// astra-review.md). The pickers used to call `XFile.readAsBytes()` directly,
/// which buffers a multi-GB pick before any limit can run. This helper:
///
/// 1. asks the OS for the length first and rejects an obviously oversized
///    pick without opening it (cheap, but `length()` comes from the
///    filesystem and a content provider can lie or the file can grow);
/// 2. then streams the content and counts bytes as they arrive, failing
///    closed the moment the running total passes the cap — so a lying
///    length never buys more than one extra chunk of buffering.
///
/// Returns `null` when the file is too large; the caller shows a fixed safe
/// message. Never throws for the oversize case.
///
/// Pattern borrowed from the repo's own `BoundedCoverFetcher` (streaming body
/// with a running cap), itself modelled on Signal Android's BackupImporter.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;

/// Reads [file] fully if it holds at most [maxBytes]; otherwise returns null.
///
/// The cap is inclusive: a file of exactly [maxBytes] is accepted.
Future<Uint8List?> readPickedFileBounded(
  XFile file, {
  required int maxBytes,
}) async {
  assert(maxBytes > 0, 'maxBytes must be positive');

  // Cheap first line: the reported length. Sufficient for honest files.
  if (await file.length() > maxBytes) return null;

  // Real guarantee: count what actually arrives.
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (builder.length + chunk.length > maxBytes) return null;
    builder.add(chunk);
  }
  return builder.takeBytes();
}
