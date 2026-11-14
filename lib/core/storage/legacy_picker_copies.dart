/// Removes the copies of picked files that the `file_selector` plugin left
/// in the app's cache folder (core/storage, decision D33).
///
/// WHY THIS EXISTS (beginner note): until 2026-11 the app let the user
/// choose a file through the `file_selector` plugin. On Android that plugin
/// also wrote a second, plain copy of every chosen file into the app's
/// private cache, as `<cache>/<uuid>/<file name>`, and nothing ever removed
/// it. Such a copy is a library export, or a whole backup that was chosen
/// for a restore. The plugin is no longer part of the app (it chooses files
/// through its own picker now, `document_picker.dart`), so no new copy is
/// made. This class removes the old ones.
///
/// HOW A COPY IS RECOGNISED. The cache folder is shared with other code, so
/// the rules are narrow on purpose:
///
///  1. Only a REAL directory directly inside the cache root whose name is a
///     UUID of VERSION 3 in lower-case hex. That is the name the plugin
///     made: `UUID.nameUUIDFromBytes(<the document's address>)` (its
///     `FileUtils.java`), which sets "version 3" on every name and prints
///     it in lower case (`java/util/UUID.java`). Other code makes folders
///     that look alike: `image_picker` names its own with a RANDOM UUID,
///     which is version 4, one digit apart. Those are not touched.
///  2. Only when it holds plain files and nothing else. The plugin put one
///     file there. A folder with a folder or a link inside is something
///     else and is left alone, whole.
///  3. Its files are deleted one by one, then the empty folder. Nothing is
///     ever deleted "with everything in it", and no link is followed.
///
/// What lies in a cache may be deleted by the system at any time, so the
/// worst a wrong guess can cost is a file some other code can make again.
///
/// Best-effort by design: nothing here throws. [LegacyPickerCopies.remove]
/// answers false when something could not be removed, and the caller tries
/// again at the next app start.
///
/// ANDROID ONLY, and that is the caller's job (the provider): on other
/// systems the "temporary folder" can be one that every program shares.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// See the library doc.
final class LegacyPickerCopies {
  /// Creates the remover for the copies directly inside [cacheRoot], the
  /// app's cache folder.
  const LegacyPickerCopies({required this.cacheRoot});

  /// The app's cache folder.
  final String cacheRoot;

  /// The preference that says "this has been done": set once [remove] has
  /// answered true, so that later app starts do not look again.
  static const String removedFlagKey = 'legacy_picker_copies_removed';

  /// The folder names the plugin made: a version 3 UUID in lower-case hex.
  /// The `3` is the version; the digit after the next dash is 8, 9, a or b
  /// in every UUID Java makes (the "variant").
  static final RegExp folderNamePattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Removes every copy the plugin left. Returns true when none is left,
  /// false when something could not be removed now.
  Future<bool> remove() async {
    // A root that is a link (or is not there) is never followed.
    if (!_isRealDirectory(cacheRoot)) return true;
    final root = Directory(cacheRoot);
    var allGone = true;
    try {
      // `followLinks: false` yields a Link for a symlink, so a link named
      // like a copy's folder is skipped instead of followed.
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!folderNamePattern.hasMatch(p.basename(entity.path))) continue;
        if (!await _removeCopyFolder(entity)) allGone = false;
      }
    } on FileSystemException {
      // The cache folder could not be listed to its end.
      allGone = false;
    }
    return allGone;
  }

  /// Removes one folder of the plugin: its files, then the folder itself.
  /// A folder that holds anything but plain files is left as it is, which
  /// counts as done: it is not the plugin's. Returns false when a file or
  /// the folder could not be deleted.
  Future<bool> _removeCopyFolder(Directory folder) async {
    try {
      final files = <File>[];
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) return true;
        files.add(entity);
      }
      for (final file in files) {
        await file.delete();
      }
      // Not recursive: if something appeared in the folder meanwhile, this
      // fails and the folder stays.
      await folder.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Whether [path] is a directory itself, not a link to one and not a file.
  static bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
