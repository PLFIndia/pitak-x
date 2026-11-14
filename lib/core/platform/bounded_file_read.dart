/// Reads a file into memory WITHOUT trusting its size (core/platform,
/// AGENTS.md §3.1).
///
/// Single source of truth for "load this file, but never more than a cap"
/// (review finding M05: size limits ran only AFTER a whole file was
/// buffered). Two rules, in this order:
///
/// 1. ask the OS for the length first and reject an obviously oversized file
///    without opening it (cheap, but a length is only what the file system
///    SAYS at that moment: a file can grow);
/// 2. then stream the content and count bytes as they arrive, failing closed
///    the moment the running total passes the cap, so a wrong length never
///    buys more than one extra block of buffering.
///
/// Returns `null` when the file is too large; the caller shows a fixed safe
/// message. Never throws for the oversize case. A file that cannot be opened
/// or read throws a `FileSystemException`, which the callers catch.
///
/// WHO READS WITH THIS: the cover reader (a cover file of the library) and
/// the reader of a picked document's private copy
/// (`file_picked_document_reader.dart`). A file the user picks never comes
/// here directly: the app's own picker copies it under a cap first
/// (`document_picker.dart`).
///
/// Pattern borrowed from the repo's own `BoundedCoverFetcher` (streaming body
/// with a running cap), itself modelled on Signal Android's BackupImporter.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;

/// Reads the file at [path] fully if it holds at most [maxBytes]; otherwise
/// returns null.
///
/// The cap is inclusive: a file of exactly [maxBytes] is accepted.
Future<Uint8List?> readFileBounded(String path, {required int maxBytes}) {
  final file = File(path);
  return readBounded(
    length: file.length,
    open: file.openRead,
    maxBytes: maxBytes,
  );
}

/// The two rules of the library doc, for anything that can say how long it
/// is and hand out its bytes.
///
/// [length] is asked first; [open] is called only when that answer fits
/// under [maxBytes]. Kept apart from the file so that a test can give a
/// length that is wrong in either direction: a real file cannot be made to
/// do that on demand.
Future<Uint8List?> readBounded({
  required Future<int> Function() length,
  required Stream<List<int>> Function() open,
  required int maxBytes,
}) async {
  assert(maxBytes > 0, 'maxBytes must be positive');

  // Cheap first line: the reported length. Sufficient for honest files.
  if (await length() > maxBytes) return null;

  // Real guarantee: count what actually arrives.
  return collectBounded(open(), maxBytes: maxBytes);
}

/// Gathers every block of [chunks] into one list, or returns null as soon as
/// more than [maxBytes] bytes have arrived (the rest is then not read).
///
/// This is rule 2 of the library doc on its own, for a caller that has no
/// length to ask for.
///
/// The blocks are kept as they come, without copying each one first. That
/// is safe for a file read with `dart:io`, which hands out a NEW list for
/// every block (`_FileStream._readBlock` in the SDK's `file_impl.dart`).
Future<Uint8List?> collectBounded(
  Stream<List<int>> chunks, {
  required int maxBytes,
}) async {
  assert(maxBytes > 0, 'maxBytes must be positive');
  final builder = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    // Leaving the loop cancels the stream, which closes the file.
    if (builder.length + chunk.length > maxBytes) return null;
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Reads [file] fully if it holds at most [maxBytes]; otherwise returns null.
///
/// The form for a file the `file_selector` plugin picked. It goes when the
/// last page has moved to the app's own picker (decision D24).
///
/// The cap is inclusive: a file of exactly [maxBytes] is accepted.
Future<Uint8List?> readPickedFileBounded(XFile file, {required int maxBytes}) {
  return readBounded(
    length: file.length,
    open: file.openRead,
    maxBytes: maxBytes,
  );
}
