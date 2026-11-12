/// Builds the builder-generation covers directory during a restore
/// (infrastructure). Extracted from `restore_backup.dart` to keep that file
/// under the architecture test's size ratchet — this phase is a pure
/// function of the extracted zip entries, the manifest, and the two covers
/// directories.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

/// Zip entry prefix for bundled cover images (restore-reader contract).
const String coverEntryPrefix = 'cover_';

/// The file name the archive entry [entryName] is restored under, or null
/// when it is not a cover picture this app would write.
///
/// THE ONE RULE for "is this entry a cover, and what is its file called"
/// (backup rework BR6). Whoever lists the covers of an archive asks here,
/// so the covers that are written and the covers the publishing record
/// believes in can never be two different sets.
///
/// The entry must be called `cover_<name>`, and `<name>` must be a file
/// name [CoverPaths.leafOf] accepts unchanged: not empty, no `..`, no `/`,
/// no `:`, and nothing that trimming would alter. That is the zip-slip and
/// path-trick defence, and it is the same rule an item's cover reference
/// has to pass, so no item can ever point at a file this refuses.
String? restorableCoverLeaf(String entryName) {
  if (!entryName.startsWith(coverEntryPrefix)) return null;
  final leaf = entryName.substring(coverEntryPrefix.length);
  return CoverPaths.leafOf('${CoverPaths.prefix}$leaf') == leaf ? leaf : null;
}

/// Writes the builder's covers directory: the archive's covers when present,
/// otherwise a copy of the active generation's. Fails closed (throws) — the
/// builder is not live, so there is no reason to accept a partial set.
void buildRestoredCovers(
  Map<String, Uint8List> files,
  BackupManifest manifest, {
  required String activeCoversDir,
  required String builderCoversDir,
}) {
  final target = Directory(builderCoversDir)..createSync(recursive: true);
  if (manifest.hasCovers) {
    for (final entry in files.entries) {
      if (!entry.key.startsWith(coverEntryPrefix)) continue;
      final leaf = entry.key.substring(coverEntryPrefix.length);
      // Defence in depth: re-validate via CoverPaths (zip-slip / traversal).
      if (CoverPaths.leafOf('${CoverPaths.prefix}$leaf') != leaf) continue;
      File(p.join(target.path, leaf)).writeAsBytesSync(entry.value);
    }
    return;
  }
  final current = Directory(activeCoversDir);
  if (!current.existsSync()) return;
  for (final entity in current.listSync()) {
    if (entity is! File) continue;
    entity.copySync(p.join(target.path, p.basename(entity.path)));
  }
}
