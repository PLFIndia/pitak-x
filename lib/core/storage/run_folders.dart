/// Private work folders that are safe to delete (core/storage).
///
/// WHY THIS EXISTS (beginner note): several parts of the app need a private
/// folder for ONE piece of work (a backup being built, a picked file being
/// read) and must remove it afterwards, because such a folder holds a plain
/// copy of the user's data. Deleting folders is dangerous code: one wrong
/// path and something else is gone. So the rules for it live here once, and
/// every user gets the same ones.
///
/// Layout: every such folder (a "run") lies directly inside ONE root that
/// the app owns, and is named `<prefix>-<random>`:
///
/// ```text
/// <root>/<prefix>-<random>/     one folder per piece of work
/// ```
///
/// The rules (those of `PublishArtifactSpoolRoot`, which `FileBackupWorkArea`
/// adapted first; moved here unchanged in backup rework BR5b):
///
///  1. Only a REAL directory named `<prefix>-<1..64 of [A-Za-z0-9_-]>`
///     directly inside the root is ever deleted. A link, a file or any other
///     name is left alone, and a root that is itself a link is not touched.
///  2. A run that this app session is using is never swept. The set of runs
///     in use is guarded by a lock, so a sweep cannot race the work.
///
/// "In use" lives in memory only: a new app start knows of no run and may
/// sweep them all. That is the point: what a killed app left behind goes.
///
/// Cleaning up is best-effort by design. Nothing here throws for a folder
/// that cannot be deleted; the methods answer `false` and the next sweep
/// tries again.
///
/// This type is pure file IO: no secrets, no knowledge of what a run holds.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// See the library doc.
final class RunFolders {
  /// Creates the keeper of the runs directly inside [rootPath].
  ///
  /// [prefix] is the first part of every run's name: one to sixteen small
  /// letters (for example `run`). Anything else is a mistake in the calling
  /// code and throws.
  ///
  /// [legacyDirectory] is ONE fixed folder of an older app version that is
  /// no longer written, only removed by [sweep] when it is still there.
  RunFolders({
    required String rootPath,
    required this.prefix,
    this.legacyDirectory,
  }) : rootPath = p.normalize(p.absolute(rootPath)),
       namePattern = namePatternFor(prefix);

  static final RegExp _prefixPattern = RegExp(r'^[a-z]{1,16}$');

  /// The names a run may have for [prefix]: `<prefix>-<1..64 of
  /// [A-Za-z0-9_-]>`. Throws for a prefix that is not 1 to 16 of a-z.
  static RegExp namePatternFor(String prefix) {
    if (!_prefixPattern.hasMatch(prefix)) {
      throw ArgumentError.value(prefix, 'prefix', 'must be 1 to 16 of a-z');
    }
    return RegExp('^$prefix-[A-Za-z0-9_-]{1,64}\$');
  }

  /// The root, as one tidy absolute path. Every run path is built from this
  /// exact text, so two spellings of the same folder can never be mistaken
  /// for two folders.
  final String rootPath;

  /// First part of every run's name.
  final String prefix;

  /// Path of the old fixed folder, or null when there is none to sweep.
  final String? legacyDirectory;

  /// The only folder names that are ever deleted inside [rootPath].
  final RegExp namePattern;

  /// Paths of the runs this app session is using.
  final Set<String> _inUse = <String>{};
  Future<void> _lock = Future<void>.value();

  /// Creates a fresh, empty run and returns its path, or null when the
  /// folder could not be made.
  ///
  /// With [sweepFirst], whatever earlier work left behind is removed before
  /// (best-effort: something stale that cannot be deleted does not stop the
  /// new run). The new run counts as "in use" until [discard].
  Future<String?> create({bool sweepFirst = false}) => _serialized(() async {
    if (sweepFirst) await _sweepAll();
    try {
      final root = Directory(rootPath);
      await root.create(recursive: true);
      final run = await root.createTemp('$prefix-');
      _inUse.add(run.path);
      return run.path;
    } on Exception {
      return null;
    }
  });

  /// Takes over a run that someone else made (for example the Android side
  /// of the app) and marks it "in use".
  ///
  /// [path] is the run folder itself or something directly inside it.
  /// Returns the run folder's path, or null when [path] does not belong to
  /// a run of this root, or the run (or the root) is not a real directory.
  /// Nothing is created and nothing is deleted here.
  Future<String?> adopt(String path) => _serialized(() async {
    final run = _runFolderOf(path);
    if (run == null) return null;
    if (!_isRealDirectory(rootPath) || !_isRealDirectory(run)) return null;
    _inUse.add(run);
    return run;
  });

  /// Removes the run that [path] belongs to: the run folder itself, or
  /// something directly inside it.
  ///
  /// Any other path is ignored (and counts as done), so a wrong argument can
  /// never delete something else. May be called twice. Returns false when
  /// the folder is still there; the next [sweep] tries again.
  Future<bool> discard(String path) => _serialized(() async {
    final run = _runFolderOf(path);
    // Not a run of this root: nothing of ours to remove.
    if (run == null) return true;
    // From here on the run is no longer "in use": if deleting fails now,
    // the next sweep may try again.
    _inUse.remove(run);
    return _deleteRealDirectory(run);
  });

  /// Removes every run that is not in use, and the legacy folder. Returns
  /// false when something could not be removed now.
  Future<bool> sweep() => _serialized(_sweepAll);

  /// The run folder [path] belongs to, or null when [path] is neither a run
  /// folder directly under the root nor something directly inside one.
  ///
  /// The path is tidied first (`a/../b` becomes `b`), so `..` cannot be used
  /// to climb out of the root.
  String? _runFolderOf(String path) {
    final tidy = p.normalize(p.absolute(path));
    for (final candidate in [tidy, p.dirname(tidy)]) {
      if (p.equals(p.dirname(candidate), rootPath) &&
          namePattern.hasMatch(p.basename(candidate))) {
        return candidate;
      }
    }
    return null;
  }

  Future<bool> _sweepAll() async {
    final runsGone = await _sweepRuns();
    final legacyGone = await _sweepLegacy();
    return runsGone && legacyGone;
  }

  /// Deletes every run folder under the root that is not in use. Returns
  /// false when one could not be deleted.
  Future<bool> _sweepRuns() async {
    // A root that is a link (or a file) is never followed or deleted.
    if (!_isRealDirectory(rootPath)) return true;
    var ok = true;
    try {
      // `followLinks: false` yields a Link for a symlink, so a link named
      // like a run is skipped instead of deleting what it points at.
      await for (final entity in Directory(rootPath).list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!namePattern.hasMatch(p.basename(entity.path))) continue;
        if (_inUse.contains(entity.path)) continue;
        if (!await _deleteRealDirectory(entity.path)) ok = false;
      }
    } on Exception {
      ok = false;
    }
    return ok;
  }

  /// Deletes the fixed folder of older app versions, if it is there.
  /// Returns false when it could not be deleted.
  Future<bool> _sweepLegacy() async {
    final legacy = legacyDirectory;
    return legacy == null || await _deleteRealDirectory(legacy);
  }

  /// Whether [path] is a directory itself, not a link to one and not a file.
  static bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  /// Deletes [path] with everything in it when it is a real directory.
  /// A link or a file at [path] is left alone (that counts as done: it is
  /// not ours). Returns false when a real directory could not be deleted.
  ///
  /// Deleting does not follow links INSIDE the folder either: `dart:io`
  /// removes a link itself, never what it points at.
  static Future<bool> _deleteRealDirectory(String path) async {
    try {
      if (!_isRealDirectory(path)) return true;
      await Directory(path).delete(recursive: true);
      return true;
    } on Exception {
      return false;
    }
  }

  /// Runs [action] with the lock held, so a sweep cannot interleave with
  /// the creation, the adoption or the removal of a run.
  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _lock;
    final gate = Completer<void>();
    _lock = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}
