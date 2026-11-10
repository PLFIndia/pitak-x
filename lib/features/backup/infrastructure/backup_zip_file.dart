/// Packs the planned entries of a backup into a ZIP FILE and puts the
/// finished file in its place (backup infrastructure, backup rework BR4;
/// closes review finding P3-B1).
///
/// WHY THIS FILE EXISTS (beginner note): until BR4 the whole ZIP was built
/// in memory and then handed on as one block of bytes. A library with
/// thousands of cover pictures needs hundreds of megabytes that way, more
/// than a phone gives an app. Here the ZIP goes straight to a file, and
/// only a small part of it is in memory at any moment.
///
/// How each kind of entry is written:
///  - a TEXT entry (manifest, the JSON entries, the vault's key blob) is in
///    memory anyway and is deflated (compressed), as before;
///  - a COVER PICTURE is read whole, one at a time, and STORED without
///    compression. A JPEG does not shrink when it is compressed again, so
///    deflating it only cost time. One picture is at most a few megabytes;
///  - a DATABASE is STREAMED: read from its file in small pieces and
///    deflated as it goes, so even a large one never sits in memory. A ZIP
///    writer cannot know the compressed size of such an entry in advance,
///    so it writes the sizes BEHIND the data (the ZIP format calls this a
///    "data descriptor"). The app's reader accepts that.
///
/// The ZIP is written to a temporary name first and moved to its final name
/// only when it is complete and not larger than a backup may be. So a file
/// with the final name is always a whole backup.
///
/// Uses `package:archive` (`ZipEncoder`, `OutputFileStream`,
/// `InputFileStream`); read in version 4.6.0 for BR4. This file never names
/// the folder the pictures come from: it gets finished [PlannedBackupEntry]
/// values and two paths.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';

/// What [packBackupZip] did: how large the ZIP file is, and whether it now
/// lies at its final path (`inPlace`). It is NOT in place when it came out
/// larger than allowed; the caller then reports that and throws the
/// temporary file away.
typedef PackedBackup = ({int sizeBytes, bool inPlace});

/// Writes [entries], in order, as a ZIP to [partPath]. When the result is
/// at most [maxArchiveBytes] long it is renamed to [finalPath], which must
/// be on the same disk (the app keeps both in one folder tree).
///
/// Throws when an entry cannot be read, when an entry is no longer the size
/// the checks judged ([PlannedBackupEntry.bytes]), or when the disk is
/// full. The caller deletes [partPath] in that case; [finalPath] is never
/// created.
PackedBackup packBackupZip({
  required List<PlannedBackupEntry> entries,
  required String partPath,
  required String finalPath,
  required int maxArchiveBytes,
}) {
  final out = OutputFileStream(partPath);
  final int written;
  try {
    final encoder = ZipEncoder()..startEncode(out);
    for (final entry in entries) {
      _add(encoder, entry);
    }
    encoder.endEncode();
    written = out.length;
  } finally {
    // Always release the file, also when an entry failed half-way.
    out.closeSync();
  }

  // What is on disk must be what the encoder says it wrote. A difference
  // would mean a lost write: never hand such a file to the user.
  final part = File(partPath);
  final sizeBytes = part.lengthSync();
  if (sizeBytes != written) {
    throw StateError(
      'The backup file is $sizeBytes bytes on disk; $written were written',
    );
  }
  // The reader also caps the FILE size. Names and the ZIP directory add a
  // little to the content, so this can only be known at the end.
  if (sizeBytes > maxArchiveBytes) {
    return (sizeBytes: sizeBytes, inPlace: false);
  }

  part.renameSync(finalPath);
  return (sizeBytes: sizeBytes, inPlace: true);
}

/// Adds one entry to the ZIP, in the way the library doc describes.
void _add(ZipEncoder encoder, PlannedBackupEntry entry) {
  final path = entry.streamPath;
  if (path == null) {
    // Read whole. `content()` throws if the size is not the judged one.
    final content = entry.content();
    encoder.add(
      entry.isCover
          ? ArchiveFile.noCompress(entry.name, content.length, content)
          : ArchiveFile.bytes(entry.name, content),
    );
    return;
  }

  final input = InputFileStream(path);
  try {
    // Same rule as `content()`, for a file that is not read whole: it must
    // still be the size the checks judged, or the build fails as a whole.
    if (input.length != entry.bytes) {
      throw StateError(
        'Backup entry "${entry.name}" changed size while the backup was '
        'being built',
      );
    }
    encoder.add(ArchiveFile.stream(entry.name, input));
  } finally {
    input.closeSync();
  }
}
