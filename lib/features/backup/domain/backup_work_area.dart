/// Where a backup is built, and who cleans up afterwards (backup domain
/// port, backup rework BR4; answers safety-check points SC6 and SC7).
///
/// WHY THIS PORT EXISTS (beginner note): since BR4 a backup is written to a
/// FILE instead of being held in memory. A file does not go away by itself
/// the way memory does, and this one is a plain copy of the whole library.
/// So every build gets its own private folder (a "run"), and there is one
/// place that knows how to remove it. The use case and the page ask for the
/// clean-up through this interface; the file work itself lives in
/// infrastructure, because the application layer must not import `dart:io`.
///
/// The three moments a run is removed:
///  1. the build failed: the use case discards it at once;
///  2. the backup was handed to the share sheet (or the page was left):
///     the page discards it;
///  3. the app was killed in between: `sweep` removes it at the next start
///     and before the next backup.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Hands out and removes the private folders backups are built in.
abstract interface class BackupWorkArea {
  /// Creates a fresh, empty folder for ONE build and returns its path.
  ///
  /// Whatever earlier builds left behind is removed first. The new folder
  /// counts as "in use" until [discard] is called for it, so no sweep of
  /// this app session deletes it.
  Future<Either<Failure, String>> createRun();

  /// Removes the run that [path] belongs to: the run folder itself, or a
  /// file directly inside it (the finished backup).
  ///
  /// Any other path is ignored (and counts as done), so a wrong argument can
  /// never delete something else. Never throws, and may be called twice. A
  /// [Failure] means the folder is still there; the next [sweep] tries again.
  Future<Either<Failure, Unit>> discard(String path);

  /// Removes every run that no build of this app session is using.
  ///
  /// Never throws. A [Failure] means something could not be removed now;
  /// the next sweep tries again.
  Future<Either<Failure, Unit>> sweep();
}
