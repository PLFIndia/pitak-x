/// Read-only access to the user's saved libraries for the background event
/// check (PLAN.md §2).
///
/// Why this is NOT `NetworkRepository` (beginner note): the repository is
/// backed by the app's live Drift connection, whose open path can run
/// migrations and repairs. A background worker that ran those while the
/// foreground app was also open would be a second writer to the same file.
/// This port is deliberately narrower — two reads, nothing else — and its
/// implementation opens its own short-lived, read-only SQLite connection.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// Hard cap on watched rows (PLAN.md decision 15). Realistic use is well
/// under 20; the cap exists so an absurd catalogue can never make the
/// worker loop for minutes. Exceeding it is a visible [CapacityFailure],
/// never a silent subset.
const int maxWatchedLibraries = 100;

/// Outcome of re-checking whether one saved row is still present and
/// unchanged (PLAN.md §2 "point-membership recheck").
enum WatchedMembership {
  /// The row exists with the same id, creation time, URL and a user-saved
  /// source. Acting on its behalf is still allowed.
  stillWatched,

  /// The row is gone, has been replaced by a different row, or its source is
  /// no longer `bookmark`/`card`. Anything pending for it must be dropped.
  removed,
}

/// Bounded, strictly filtered reads of the `network_libraries` table.
abstract interface class WatchedLibrariesSource {
  /// Every row whose RAW `source` token is exactly `bookmark` or `card`,
  /// with a canonical site URL, in stable URL order.
  ///
  /// Returns [CapacityFailure] when more than [maxWatchedLibraries] rows
  /// qualify, [StorageFailure] when the database cannot be read right now
  /// (missing file, missing table, busy/hot journal). Never repairs anything.
  Future<Either<Failure, List<WatchedLibrary>>> snapshot();

  /// Re-reads ONE row by its full [identity] and reports whether it is still
  /// a user-saved library (PLAN.md §2: checked before every fetch, commit
  /// and notification).
  ///
  /// A read error is a [StorageFailure], never [WatchedMembership.removed]:
  /// "could not check" must not be mistaken for "the user removed it", and
  /// must not authorize the action either (callers fail closed).
  Future<Either<Failure, WatchedMembership>> membership(
    WatchedLibraryIdentity identity,
  );
}
