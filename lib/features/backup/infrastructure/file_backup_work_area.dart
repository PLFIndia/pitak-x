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
/// `PublishArtifactSpoolRoot` (publish feature). Since BR5b they live in
/// [RunFolders] (`core/storage/run_folders.dart`), because the file a
/// restore picks needs the very same ones:
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
///
/// What is left in this file: the names (`backup_work`, `run-…`), the old
/// Documents folder, and turning [RunFolders]' plain answers into the typed
/// results of the domain port.
library;

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/run_folders.dart';
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
  /// Built by [RunFolders] from the same prefix the runs are made with, so
  /// this text and the deleting code cannot disagree.
  static final RegExp runNamePattern = RunFolders.namePatternFor(_runPrefix);

  /// First part of every run folder's name.
  static const String _runPrefix = 'run';

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

  /// The keeper of the run folders: which exist, which are in use, and the
  /// only code that deletes one. Made on first use, when [tempRoot] and
  /// [legacyWorkDir] are known.
  late final RunFolders _runs = RunFolders(
    rootPath: p.join(tempRoot, directoryName),
    prefix: _runPrefix,
    legacyDirectory: legacyWorkDir,
  );

  @override
  Future<Either<Failure, String>> createRun() async {
    // The sweep before the new run is best-effort: something stale that
    // cannot be deleted must not stop a backup. The typed result is
    // available from [sweep].
    final run = await _runs.create(sweepFirst: true);
    return run == null
        ? left<Failure, String>(_createFailed)
        : right<Failure, String>(run);
  }

  @override
  Future<Either<Failure, Unit>> discard(String path) async =>
      _removed(await _runs.discard(path));

  @override
  Future<Either<Failure, Unit>> sweep() async => _removed(await _runs.sweep());

  Either<Failure, Unit> _removed(bool gone) =>
      gone ? right<Failure, Unit>(unit) : left<Failure, Unit>(_removeFailed);
}
