/// The private file of one export, on disk (import/export infrastructure;
/// review finding P4-M6, decisions D167 and D172). Implements the domain
/// port [ExportWorkArea].
///
/// Layout, under the app's TEMPORARY folder (private to the app):
///
/// ```text
/// <temp>/export_work/run-<random>/<name>     one folder per export (a "run")
/// ```
///
/// This is the layout a backup has (`FileBackupWorkArea`), on purpose: the
/// app's Android code saves a file only when it lies exactly there
/// (`DocumentCopyOut.kt`), in one of two folders, in a run, under a name
/// that [isSavableFileName] allows. `test/architecture/
/// document_saving_test.dart` holds the two sides to one text.
///
/// The rules that make deleting safe are those of [RunFolders]
/// (`core/storage/run_folders.dart`): only a real folder named `run-…`
/// directly inside `export_work` is ever deleted, and a run this app
/// session is using is never swept.
///
/// Cleaning up is best-effort by design: a folder that cannot be deleted
/// must never stop an export, and the next sweep tries again.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/features/import_export/domain/export_work_area.dart';

/// See the library doc.
final class FileExportWorkArea implements ExportWorkArea {
  /// Creates the work area under [tempRoot] (the app's temporary folder,
  /// which on Android is the cache folder the native side reads from).
  FileExportWorkArea({required this.tempRoot});

  /// Folder name under [tempRoot]; the only folder runs are created in. The
  /// same text as `DocumentCopyOut.FOLDER_EXPORT` in Kotlin.
  static const String directoryName = 'export_work';

  /// The only folder names that are ever deleted inside [directoryName].
  /// Built by [RunFolders] from the same prefix the runs are made with.
  static final RegExp runNamePattern = RunFolders.namePatternFor(_runPrefix);

  /// First part of every run folder's name.
  static const String _runPrefix = 'run';

  /// Path of the app's temporary folder.
  final String tempRoot;

  static const Failure _putFailed = StorageFailure(
    'Could not prepare the export file on this device.',
  );
  static const Failure _removeFailed = StorageFailure(
    'Could not remove temporary export files.',
  );

  /// The keeper of the run folders: which exist, which are in use, and the
  /// only code that deletes one.
  late final RunFolders _runs = RunFolders(
    rootPath: p.join(tempRoot, directoryName),
    prefix: _runPrefix,
  );

  @override
  Future<Either<Failure, String>> put({
    required String fileName,
    required Uint8List bytes,
  }) async {
    // BEFORE anything is made: a name that could leave the run folder, or
    // that the saving side would refuse anyway, never becomes a path.
    if (!isSavableFileName(fileName)) return left(_putFailed);
    // The sweep before the new run is best-effort, as for a backup.
    final run = await _runs.create(sweepFirst: true);
    if (run == null) return left(_putFailed);
    final path = p.join(run, fileName);
    try {
      // `flush`: the file is handed on by its path at once, so every byte
      // has to be in it when this returns.
      await File(path).writeAsBytes(bytes, flush: true);
      return right(path);
    } on FileSystemException {
      // No room, most likely. The half-written file must not stay.
      await _runs.discard(run);
      return left(_putFailed);
    }
  }

  @override
  Future<Either<Failure, Unit>> discard(String path) async =>
      _removed(await _runs.discard(path));

  @override
  Future<Either<Failure, Unit>> sweep() async => _removed(await _runs.sweep());

  Either<Failure, Unit> _removed(bool gone) =>
      gone ? right<Failure, Unit>(unit) : left<Failure, Unit>(_removeFailed);
}
