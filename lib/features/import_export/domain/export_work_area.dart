/// Where ONE export's file lies while it is saved or shared, and who cleans
/// up afterwards (import/export domain port; review finding P4-M6,
/// decisions D167 and D172).
///
/// WHY THIS PORT EXISTS (beginner note): an export is made in memory, as
/// bytes. To save it where the user says, the app's Android code needs a
/// FILE it can copy, and sharing a file by its path leaves one plain copy
/// less in the cache than sharing bytes did. So the bytes are put into a
/// private folder of their own (a "run"), under the name the user should
/// see, for the length of one call. A file does not go away by itself the
/// way memory does, and an export is a plain copy of the library: there is
/// one place that knows how to remove it, and this is its interface. The
/// file work itself lives in infrastructure, because the application layer
/// must not import `dart:io`. `BackupWorkArea` is the same idea for a
/// backup.
///
/// The moments a run is removed:
///  1. the save window or the share sheet has answered, whatever the
///     answer: the controller discards it;
///  2. the app was killed in between: `sweep` removes it at the next start
///     and before the next export.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Keeps and removes the private file of one export.
abstract interface class ExportWorkArea {
  /// Writes [bytes] into a fresh private folder under [fileName] and returns
  /// the path of that file.
  ///
  /// [fileName] must be a name a file may be saved under (plain letters,
  /// digits and hyphens with one of the four endings the app makes); any
  /// other name is refused BEFORE a byte is written. Whatever earlier
  /// exports left behind is removed first. The new folder counts as "in
  /// use" until [discard] is called for it. Never throws.
  Future<Either<Failure, String>> put({
    required String fileName,
    required Uint8List bytes,
  });

  /// Removes the run that [path] belongs to: the run folder itself, or the
  /// file directly inside it.
  ///
  /// Any other path is ignored (and counts as done), so a wrong argument can
  /// never delete something else. Never throws, and may be called twice. A
  /// [Failure] means the folder is still there; the next [sweep] tries again.
  Future<Either<Failure, Unit>> discard(String path);

  /// Removes every run that no export of this app session is using.
  ///
  /// Never throws. A [Failure] means something could not be removed now;
  /// the next sweep tries again.
  Future<Either<Failure, Unit>> sweep();
}
