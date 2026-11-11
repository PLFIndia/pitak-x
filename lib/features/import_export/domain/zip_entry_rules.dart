/// The rules a ZIP entry has to keep BEFORE a reader unpacks it
/// (import/export domain, ADR 0009).
///
/// WHY THIS FILE EXISTS (beginner note): a ZIP file's directory makes
/// claims about every entry: its name, its sizes, how it is packed. A
/// reader that trusts those claims can be led to write outside its folder
/// (a name like `../../file`) or to unpack far more than the file's size
/// suggests. The rules here look at the claims only. They read no content
/// and touch no disk, so they are plain Dart that a test can run on a
/// record made by hand.
///
/// Since BR5 the app has two ZIP readers until the older one is removed
/// (BR7): `BoundedZipExtractor`, which holds the archive in memory, and the
/// reader that works from a file. Both call the rules in this file, so one
/// rule cannot mean two things.
library;

import 'package:pitaka/features/import_export/domain/zip_container.dart';

/// Thrown on any limit violation or structural anomaly (zip-slip, empty name,
/// nested name, duplicate, directory entry). Distinct from IO errors so callers
/// can show "archive looks corrupt or hostile" without conflating causes.
class BoundedExtractionException implements Exception {
  /// Creates the exception with a human-readable [message].
  const BoundedExtractionException(this.message);

  /// Why extraction was rejected.
  final String message;

  @override
  String toString() => 'BoundedExtractionException: $message';
}

/// The name under which the entry [header] is handed out: its LEAF, checked.
///
/// Name checks: leaf-only, non-empty, no separators/NUL, unique, a file.
/// [isTaken] says whether an earlier entry of the same archive already has
/// that leaf name.
///
/// Uses the CENTRAL directory name (spoof-safe; the local header's name is
/// ignored, cf. archive issue #266). "Directory" here means either a
/// trailing slash or a UNIX mode that is not a regular file (symlink,
/// device, ...), mirroring what `ZipDecoder` would have classified — but
/// refused instead of followed.
///
/// Throws [BoundedExtractionException] for a name that breaks a rule.
String zipLeafName(
  ZipDirectoryEntry header, {
  required bool Function(String leaf) isTaken,
}) {
  final rawName = header.name;
  if (!_isRegularFile(header)) {
    throw BoundedExtractionException(
      "Archive contains a directory entry: '$rawName'",
    );
  }

  // Reduce to leaf; strip any directory component (zip-slip defence).
  final leaf = rawName.split('/').last.split(r'\').last;
  if (leaf.trim().isEmpty) {
    throw BoundedExtractionException(
      "Archive entry has an empty filename: '$rawName'",
    );
  }
  if (leaf.contains('/') || leaf.contains(r'\') || leaf.contains('\u0000')) {
    throw BoundedExtractionException(
      "Archive entry has an unsafe filename: '$rawName'",
    );
  }
  if (isTaken(leaf)) {
    throw BoundedExtractionException(
      "Archive has duplicate entry name: '$leaf'",
    );
  }
  return leaf;
}

/// Same classification `ZipDecoder.decodeBuffer` applies: for UNIX-made
/// entries (`versionMadeBy` high byte 3) the file type lives in the high
/// 16 bits of the external attributes; anything but "regular" (0x8000) or
/// "unspecified" (0x0000) is not a plain file. For other hosts only a
/// trailing slash marks a directory.
bool _isRegularFile(ZipDirectoryEntry header) {
  if (header.name.endsWith('/')) return false;
  if ((header.versionMadeBy >> 8) == 3) {
    final mode = header.externalAttributes >> 16;
    final fileType = mode & 0xF000;
    return fileType == 0x8000 || fileType == 0x0000;
  }
  return true;
}
