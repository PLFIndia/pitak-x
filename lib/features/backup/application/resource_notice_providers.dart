/// The resource notice of a backup and of a restore, worked out
/// (application layer, backup rework BR9, decisions D5, D48 and D50).
///
/// WHY THIS FILE EXISTS (beginner note): the rules of the notice are pure
/// numbers (`domain/resource_notice.dart`). The numbers come from two
/// places outside: the device says how much it has (`DeviceResources`), and
/// the files of the library say how large it is
/// (`LibraryFootprintSource`). The two providers here ask both, hand the
/// answers to the rules, and give the page one finished [ResourceNotice].
///
/// THE NOTICE NEVER BLOCKS (decision D5). So neither provider ever fails:
/// a source that throws counts as "could not be read", and the notice says
/// so. The page shows the result and lets the user go on whatever it says.
///
/// Both providers are auto-disposed (the default): the figures are read
/// when the notice opens and forgotten when it closes. They are shown once
/// and never stored, logged or sent.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_resources.dart';
import 'package:pitaka/features/backup/domain/library_footprint.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'resource_notice_providers.g.dart';

/// What a backup of the library as it is now needs, against what this
/// device has.
@riverpod
Future<ResourceNotice> backupResourceNotice(BackupResourceNoticeRef ref) async {
  final (device, library) = await (
    _deviceFacts(ref.watch(deviceResourcesProvider)),
    _footprint(ref.watch(libraryFootprintSourceProvider)),
  ).wait;
  return _judge(
    device,
    storageNeedBytes: library == null ? null : backupStorageNeedBytes(library),
  );
}

/// What a restore of the chosen backup still needs, against what this
/// device has. [archive] is what the inspection of the backup found
/// (`ArchiveInspection.sizes`).
@riverpod
Future<ResourceNotice> restoreResourceNotice(
  RestoreResourceNoticeRef ref,
  RestoreArchiveSizes archive,
) async {
  final (device, library) = await (
    _deviceFacts(ref.watch(deviceResourcesProvider)),
    _footprint(ref.watch(libraryFootprintSourceProvider)),
  ).wait;
  return _judge(
    device,
    storageNeedBytes: library == null
        ? null
        : restoreStorageNeedBytes(archive: archive, library: library),
  );
}

ResourceNotice _judge(
  DeviceResourceFacts device, {
  required int? storageNeedBytes,
}) => ResourceNotice.judge(
  storageNeedBytes: storageNeedBytes,
  storageFreeBytes: device.freeStorageBytes,
  memoryAvailableBytes: device.availableMemoryBytes,
  memoryLowThresholdBytes: device.lowMemoryThresholdBytes,
  memoryLow: device.lowMemory,
);

/// What the device says, or "nothing could be read" when asking failed.
Future<DeviceResourceFacts> _deviceFacts(DeviceResources resources) async {
  try {
    return await resources.read();
  } on Object {
    // Deliberately not rethrown and not logged: the port already answers
    // "unknown" for every failure it knows. This catches the one it does
    // not, so that a notice can never stop a backup or a restore (D5).
    return DeviceResourceFacts.unknown;
  }
}

/// The size of the library, or null when it could not be read.
Future<LibraryFootprint?> _footprint(LibraryFootprintSource source) async {
  try {
    return await source.read();
  } on Object {
    // As above: "could not be read" is an answer, not an error.
    return null;
  }
}
