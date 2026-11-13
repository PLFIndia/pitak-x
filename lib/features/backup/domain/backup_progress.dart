/// How far a running backup has come (backup domain; backup rework BR4,
/// rider 3; the backup part of review finding P4-M7).
///
/// WHY THIS FILE EXISTS (beginner note): a backup of a large library takes
/// a while, and almost all of that time goes into packing cover pictures.
/// A spinner alone does not say whether the app is still working or how
/// long it may take. "Cover 1,234 of 9,000" does. This file holds the two
/// numbers of that sentence and the shape of the function that receives
/// them; who counts and who shows them is decided elsewhere.
///
/// Pure Dart: no Flutter, no IO, no Riverpod (AGENTS.md §3.1).
library;

/// The covers packed so far, of all covers this backup will hold.
///
/// A Value Object (AGENTS.md §3.3): there is no public constructor, only
/// [BackupProgress.tryCreate], which checks the two numbers. So a
/// `BackupProgress` anywhere in the app always reads sensibly: at least
/// one cover in total, and never more done than there are.
final class BackupProgress {
  // Private on purpose: the only way in is tryCreate, which validates.
  const BackupProgress._(this.coversDone, this.coversTotal);

  /// Builds a progress value, or null when the numbers make no sense:
  /// [coversTotal] below 1, or [coversDone] below 0 or above [coversTotal].
  ///
  /// Why null and not an exception (beginner note): the numbers arrive as a
  /// message from another isolate. A message that does not fit is simply
  /// not shown; it must never be able to stop a backup.
  static BackupProgress? tryCreate({
    required int coversDone,
    required int coversTotal,
  }) {
    if (coversTotal < 1) return null;
    if (coversDone < 0 || coversDone > coversTotal) return null;
    return BackupProgress._(coversDone, coversTotal);
  }

  /// Cover pictures already written into the backup file.
  final int coversDone;

  /// Cover pictures this backup will hold when it is finished. A picture
  /// that is left out because it is too large is not counted.
  final int coversTotal;

  @override
  String toString() => 'BackupProgress($coversDone of $coversTotal)';
}

/// Receives the progress of a running backup. Called on the isolate that
/// asked for the backup, a few times a second at most, and once more when
/// the last cover is packed. Keep it cheap.
typedef BackupProgressListener = void Function(BackupProgress progress);
