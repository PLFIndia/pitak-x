/// The folders backups are built in, on disk (backup infrastructure, backup
/// rework BR4). Implements the domain port [BackupWorkArea].
///
/// Layout, under the app's TEMPORARY folder (private to the app):
///
/// ```text
/// <temp>/backup_work/run-<random>/     one folder per build (a "run")
/// ```
///
/// WHY THE TEMPORARY FOLDER (beginner note): until BR4 the work folder lay
/// under Documents with one fixed name. Documents is never cleared by the
/// system, so a backup that was killed half-way left a plain copy of the
/// library there for good. The publish feature had the same problem and
/// moved to the temporary folder (fix-plan L5); this follows it.
///
/// WHY ONE FOLDER PER BUILD: with one fixed name, a build that was still
/// running after its page was left and a second build started from a new
/// page deleted each other's files.
///
/// The rules that make deleting safe are the ones of
/// `PublishArtifactSpoolRoot` (publish feature), adapted here:
///
///  1. Only a REAL directory named `run-<1..64 of [A-Za-z0-9_-]>` directly
///     inside the app's own `backup_work` folder is ever deleted. A link, a
///     file or any other name is left alone, and a `backup_work` that is
///     itself a link is not touched at all.
///  2. A run this app session is using is never swept. The set of runs in
///     use is guarded by a lock, so a sweep cannot race a build.
///
/// Cleaning up is best-effort by design: a folder that cannot be deleted
/// must never stop a backup, and the next sweep tries again. `sweep` and
/// `discard` still report such a failure as a typed value, for callers and
/// tests that care.
library;

import 'dart:async';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_work_area.dart';

/// See the library doc.
final class FileBackupWorkArea implements BackupWorkArea {
  /// Creates the work area under [tempRoot] (the app's temporary folder).
  ///
  /// [legacyWorkDir] is the fixed work folder of app versions before BR4
  /// (`<Documents>/backup_create_work`). It is never written any more, only
  /// removed by [sweep] when a killed backup of an older version left it.
  FileBackupWorkArea({required this.tempRoot, this.legacyWorkDir});

  /// Folder name under [tempRoot]; the only folder runs are created in.
  static const String directoryName = 'backup_work';

  /// The only folder names that are ever deleted inside [directoryName].
  static final RegExp runNamePattern = RegExp(r'^run-[A-Za-z0-9_-]{1,64}$');

  /// Path of the app's temporary folder.
  final String tempRoot;

  /// Path of the old fixed work folder, or null when there is none to sweep.
  final String? legacyWorkDir;

  static const Failure _createFailed = StorageFailure(
    'Could not prepare a folder for the backup on this device.',
  );
  static const Failure _removeFailed = StorageFailure(
    'Could not remove temporary backup files.',
  );

  /// Paths of the runs this app session is using (created, not discarded).
  final Set<String> _inUse = <String>{};
  Future<void> _lock = Future<void>.value();

  /// The `backup_work` folder, as one tidy absolute path. Every run path is
  /// built from this exact text, so two spellings of the same folder can
  /// never be mistaken for two folders.
  late final String _rootPath = p.normalize(
    p.absolute(p.join(tempRoot, directoryName)),
  );

  @override
  Future<Either<Failure, String>> createRun() => _serialized(() async {
    // Best-effort: something stale that cannot be deleted must not stop a
    // backup. The typed result is available from [sweep].
    await _sweepAll();
    try {
      final root = Directory(_rootPath);
      await root.create(recursive: true);
      final run = await root.createTemp('run-');
      _inUse.add(run.path);
      return right<Failure, String>(run.path);
    } on Exception {
      return left<Failure, String>(_createFailed);
    }
  });

  @override
  Future<Either<Failure, Unit>> discard(String path) => _serialized(() async {
    final run = _runFolderOf(path);
    // Not a run of this work area: nothing of ours to remove.
    if (run == null) return right<Failure, Unit>(unit);
    // From here on the run is no longer "in use": if deleting fails now,
    // the next sweep may try again.
    _inUse.remove(run);
    return await _deleteRealDirectory(run)
        ? right<Failure, Unit>(unit)
        : left<Failure, Unit>(_removeFailed);
  });

  @override
  Future<Either<Failure, Unit>> sweep() => _serialized(_sweepAll);

  /// The run folder [path] belongs to, or null when [path] is neither a run
  /// folder directly under the root nor something directly inside one.
  ///
  /// The path is tidied first (`a/../b` becomes `b`), so `..` cannot be used
  /// to climb out of the root.
  String? _runFolderOf(String path) {
    final tidy = p.normalize(p.absolute(path));
    for (final candidate in [tidy, p.dirname(tidy)]) {
      if (p.equals(p.dirname(candidate), _rootPath) &&
          runNamePattern.hasMatch(p.basename(candidate))) {
        return candidate;
      }
    }
    return null;
  }

  Future<Either<Failure, Unit>> _sweepAll() async {
    final runsGone = await _sweepRuns();
    final legacyGone = await _sweepLegacy();
    return runsGone && legacyGone
        ? right<Failure, Unit>(unit)
        : left<Failure, Unit>(_removeFailed);
  }

  /// Deletes every run folder under the root that is not in use. Returns
  /// false when one could not be deleted.
  Future<bool> _sweepRuns() async {
    // A root that is a link (or a file) is never followed or deleted.
    if (FileSystemEntity.typeSync(_rootPath, followLinks: false) !=
        FileSystemEntityType.directory) {
      return true;
    }
    var ok = true;
    try {
      // `followLinks: false` yields a Link for a symlink, so a link named
      // `run-x` is skipped instead of deleting what it points at.
      await for (final entity in Directory(
        _rootPath,
      ).list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!runNamePattern.hasMatch(p.basename(entity.path))) continue;
        if (_inUse.contains(entity.path)) continue;
        if (!await _deleteRealDirectory(entity.path)) ok = false;
      }
    } on Exception {
      ok = false;
    }
    return ok;
  }

  /// Deletes the fixed work folder of versions before BR4, if it is there.
  /// Returns false when it could not be deleted.
  Future<bool> _sweepLegacy() async {
    final legacy = legacyWorkDir;
    return legacy == null || await _deleteRealDirectory(legacy);
  }

  /// Deletes [path] with everything in it when it is a real directory.
  /// A link or a file at [path] is left alone (that counts as done: it is
  /// not ours). Returns false when a real directory could not be deleted.
  ///
  /// Deleting does not follow links INSIDE the folder either: `dart:io`
  /// removes a link itself, never what it points at.
  Future<bool> _deleteRealDirectory(String path) async {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return true;
      }
      await Directory(path).delete(recursive: true);
      return true;
    } on Exception {
      return false;
    }
  }

  /// Runs [action] with the lock held, so a sweep cannot interleave with
  /// the creation or the removal of a run.
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
