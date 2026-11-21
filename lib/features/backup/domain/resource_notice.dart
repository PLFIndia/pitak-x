/// The rules of the resource notice (backup domain, backup rework BR9).
///
/// WHY THIS FILE EXISTS (beginner note): before a backup and before a
/// restore the app says how much free storage and memory the run needs, how
/// much this phone has, and whether that will do (decision D5). It only
/// INFORMS: whatever the verdict, the user may go on. This file holds the
/// rules behind that sentence and nothing else. It is pure Dart: it gets
/// numbers and gives back a verdict, so every edge can be tested without a
/// phone.
///
/// Where the numbers come from:
///  - what a run NEEDS is worked out here, from the size of the library on
///    disk ([LibraryFootprint]) and, for a restore, from the sizes the
///    chosen backup declares;
///  - what the phone HAS is read by the platform layer
///    (`core/platform/device_resources.dart`) and handed in as plain
///    numbers. A number that could not be read is null, and the verdict for
///    it is [ResourceVerdict.unknown].
library;

import 'package:pitaka/features/backup/domain/library_footprint.dart';

const int _mebibyte = 1024 * 1024;

/// How the phone's supply compares with what a run needs.
enum ResourceVerdict {
  /// The supply covers the need with room to spare.
  enough,

  /// The supply covers the need, but only just: the run may still fail.
  tight,

  /// The supply is below the need: the run will probably fail.
  notEnough,

  /// The need or the supply could not be read on this device.
  unknown,
}

/// The least room to spare, in bytes, that makes storage "enough":
/// 100 MB (decision D48), written as the app writes sizes (1 MB is
/// 1,024 × 1,024 bytes, see `display_number.dart`).
const int storageMarginFloorBytes = 100 * _mebibyte;

/// The memory a backup or a restore is counted with: 100 MB, one fixed
/// figure for both (decision D50).
///
/// Why a fixed figure (beginner note): since both runs work from files,
/// the memory they need no longer grows with the library. Measured in
/// November 2026: on a phone the app's memory rose by about 20 MB during a
/// run, with 4,000 and with 10,000 covers and up to 1 GiB; on a desktop a
/// whole tool process peaked at 69 MB for a backup of 1 GiB. 100 MB is
/// above both.
const int resourceNoticeMemoryNeedBytes = 100 * _mebibyte;

/// How much free storage beyond [needBytes] makes the verdict "enough":
/// 20% of the need, and at least [storageMarginFloorBytes] (decision D48).
///
/// The 20% are rounded UP to a whole byte, so "enough" is never said with
/// less than a fifth to spare.
int storageMarginBytes(int needBytes) {
  final fifth = (needBytes + 4) ~/ 5;
  return fifth > storageMarginFloorBytes ? fifth : storageMarginFloorBytes;
}

/// The verdict for storage (decision D48):
///
///  - [ResourceVerdict.unknown] when [needBytes] or [freeBytes] is null
///    (or negative, which no honest reading is);
///  - [ResourceVerdict.notEnough] when less than the need is free;
///  - [ResourceVerdict.enough] when at least the need plus
///    [storageMarginBytes] is free;
///  - [ResourceVerdict.tight] in between.
///
/// Why there is a "tight" (beginner note): the need is an estimate, and
/// other apps write to the phone while the run goes on. A phone with
/// exactly the need free can still run out.
ResourceVerdict storageVerdict({
  required int? needBytes,
  required int? freeBytes,
}) {
  if (needBytes == null || freeBytes == null) return ResourceVerdict.unknown;
  if (needBytes < 0 || freeBytes < 0) return ResourceVerdict.unknown;
  if (freeBytes < needBytes) return ResourceVerdict.notEnough;
  if (freeBytes >= needBytes + storageMarginBytes(needBytes)) {
    return ResourceVerdict.enough;
  }
  return ResourceVerdict.tight;
}

/// The verdict for memory (decision D50). The room to spare is not a
/// number of ours: it is the mark at which Android itself calls memory
/// low ([lowThresholdBytes]), and its own flag for "low right now"
/// ([lowNow]).
///
///  - [ResourceVerdict.unknown] when [availableBytes] is null (or
///    negative);
///  - [ResourceVerdict.notEnough] when less than [needBytes] is available;
///  - [ResourceVerdict.tight] when the phone says it is low on memory, or
///    would be below its low mark once the need is taken;
///  - [ResourceVerdict.enough] otherwise.
///
/// A low mark that could not be read counts as 0, and a flag that could
/// not be read as "not low": the figure that WAS read is still judged.
ResourceVerdict memoryVerdict({
  required int needBytes,
  required int? availableBytes,
  required int? lowThresholdBytes,
  required bool? lowNow,
}) {
  if (availableBytes == null || availableBytes < 0) {
    return ResourceVerdict.unknown;
  }
  if (availableBytes < needBytes) return ResourceVerdict.notEnough;
  // Past the line above, what is left after the need is 0 or more, so a
  // low mark of 0 (or a negative one, which no phone reports) never
  // makes the verdict "tight".
  final threshold = lowThresholdBytes ?? 0;
  if ((lowNow ?? false) || availableBytes - needBytes < threshold) {
    return ResourceVerdict.tight;
  }
  return ResourceVerdict.enough;
}

/// The free storage a backup of a library of this size needs, in bytes:
/// twice the library's size on disk.
///
/// Why twice (beginner note): the finished backup file lies in the app's
/// private folder, and the share sheet's plugin makes its own copy of it
/// before it opens. For a moment both exist. The library's size stands in
/// for the size of the file to come, which is only known once it is built;
/// it is a little high on purpose, because the databases shrink inside a
/// backup.
int backupStorageNeedBytes(LibraryFootprint library) => 2 * library.totalBytes;

/// The sizes a chosen backup declares, as far as the notice needs them.
///
/// Both numbers are sums of sizes the reader of a restore has already held
/// to the limits of a backup, so neither is larger than one backup may be.
typedef RestoreArchiveSizes = ({
  /// The unpacked size of everything a restore takes out of the backup.
  int takenBytes,

  /// The unpacked size of the databases among them.
  int databaseBytes,

  /// Whether the backup carries cover pictures.
  bool hasCovers,

  /// Whether the backup carries a borrowers vault.
  bool hasVault,
});

/// The free storage a restore of [archive] into [library] still needs, in
/// bytes, counted from the moment the notice is shown. The app's copy of
/// the chosen file exists by then, and free storage is read after it, so
/// the copy is NOT counted again.
///
/// What a restore writes before the old library goes:
///  - everything it takes out of the backup, once (the databases are
///    unpacked into a work folder, the covers into the new library);
///  - the content of the databases once more (it is written into the new
///    library);
///  - a copy of the phone's catalogue, into which that content goes;
///  - when the backup has no covers: a copy of the phone's covers;
///  - when the backup has no vault: a copy of the phone's vault.
int restoreStorageNeedBytes({
  required RestoreArchiveSizes archive,
  required LibraryFootprint library,
}) =>
    archive.takenBytes +
    archive.databaseBytes +
    library.catalogueBytes +
    (archive.hasCovers ? 0 : library.coverBytes) +
    (archive.hasVault ? 0 : library.vaultBytes);

/// What the notice says: two needs, two supplies and a verdict for each.
///
/// A value object, built by [ResourceNotice.judge] so that the verdicts
/// can never disagree with the numbers next to them.
final class ResourceNotice {
  const ResourceNotice._({
    required this.storageNeedBytes,
    required this.storageFreeBytes,
    required this.memoryNeedBytes,
    required this.memoryAvailableBytes,
    required this.storage,
    required this.memory,
  });

  /// Judges the supplies against the needs.
  ///
  /// [storageNeedBytes] is null when the size of the library could not be
  /// read. The three memory values and [storageFreeBytes] are what the
  /// device said, each null when it could not be read.
  factory ResourceNotice.judge({
    required int? storageNeedBytes,
    required int? storageFreeBytes,
    required int? memoryAvailableBytes,
    required int? memoryLowThresholdBytes,
    required bool? memoryLow,
  }) => ResourceNotice._(
    storageNeedBytes: storageNeedBytes,
    storageFreeBytes: storageFreeBytes,
    memoryNeedBytes: resourceNoticeMemoryNeedBytes,
    memoryAvailableBytes: memoryAvailableBytes,
    storage: storageVerdict(
      needBytes: storageNeedBytes,
      freeBytes: storageFreeBytes,
    ),
    memory: memoryVerdict(
      needBytes: resourceNoticeMemoryNeedBytes,
      availableBytes: memoryAvailableBytes,
      lowThresholdBytes: memoryLowThresholdBytes,
      lowNow: memoryLow,
    ),
  );

  /// The free storage the run needs; null when it could not be worked out.
  final int? storageNeedBytes;

  /// The free storage the phone has; null when it could not be read.
  final int? storageFreeBytes;

  /// The memory the run is counted with.
  final int memoryNeedBytes;

  /// The memory the phone has available; null when it could not be read.
  final int? memoryAvailableBytes;

  /// The verdict for storage.
  final ResourceVerdict storage;

  /// The verdict for memory.
  final ResourceVerdict memory;

  /// The worse of the two verdicts, in this order: not enough, tight,
  /// unknown, enough. "Unknown" ranks above "enough" on purpose: when one
  /// of the two could not be read, the notice must not say all is well.
  ResourceVerdict get overall {
    for (final verdict in const [
      ResourceVerdict.notEnough,
      ResourceVerdict.tight,
      ResourceVerdict.unknown,
    ]) {
      if (storage == verdict || memory == verdict) return verdict;
    }
    return ResourceVerdict.enough;
  }
}
