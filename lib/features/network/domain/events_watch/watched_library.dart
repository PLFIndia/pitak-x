/// A library the user deliberately saved, as seen by the background event
/// check (PLAN.md §2).
///
/// Why a separate, smaller type than `NetworkLibrary` (beginner note): the
/// background worker reads the catalogue through its own read-only SQLite
/// connection, not through the Drift repository, and it only needs four
/// facts about a row. Keeping those facts in their own immutable value makes
/// it impossible for the worker to accidentally depend on (or leak) the rest
/// of the row — location, membership flags, fingerprints — into watch state
/// or notifications.
library;

/// The identity of a saved row, used to detect "this row was removed or
/// replaced" between two reads (PLAN.md §2: pruning uses
/// `(id, createdAt, siteUrl)`, never URL membership alone).
///
/// Why three fields (beginner note): a row's `id` can be reused after a
/// delete + re-add on some databases, and the same `siteUrl` can come back as
/// a brand-new row. Only all three together say "this is the very same row
/// the worker saw before".
final class WatchedLibraryIdentity {
  /// Creates an identity. Values come from the database, already validated.
  const WatchedLibraryIdentity({
    required this.rowId,
    required this.createdAt,
    required this.siteUrl,
  });

  /// Drift primary key of the `network_libraries` row.
  final int rowId;

  /// Epoch millis when the row was created on this device.
  final int createdAt;

  /// `BookmarkUrl`-normalized published site root (the natural key).
  final String siteUrl;

  /// Field-by-field equality WITHOUT overriding `==`/`hashCode` — the repo's
  /// domain convention (see `NetworkLibrary.sameAs`; the pure domain has no
  /// `@immutable` annotation package on its allow-list).
  bool sameAs(WatchedLibraryIdentity other) =>
      other.rowId == rowId &&
      other.createdAt == createdAt &&
      other.siteUrl == siteUrl;

  @override
  String toString() => 'WatchedLibraryIdentity(#$rowId)';
}

/// One watched row: its identity plus the only display fact the worker may
/// use — the library's *public* name, when the catalogue holds one.
final class WatchedLibrary {
  /// Creates a watched row.
  const WatchedLibrary({required this.identity, required this.publicName});

  /// Stable identity of the row.
  final WatchedLibraryIdentity identity;

  /// The library's public name, or null.
  ///
  /// Non-null ONLY when the row's `fetch_status` is `ok`: a successful
  /// foreground Refresh overwrites the stored name with the one from the
  /// library's own published descriptor (`refresh_run.dart`). Until then the
  /// stored name may be a private label the user typed, which must never be
  /// shown in a notification (PLAN.md decision 13).
  final String? publicName;

  /// Convenience: the canonical site URL.
  String get siteUrl => identity.siteUrl;

  /// Field-by-field equality (see [WatchedLibraryIdentity.sameAs]).
  bool sameAs(WatchedLibrary other) =>
      other.identity.sameAs(identity) && other.publicName == publicName;

  /// Never includes the URL or name: logs must not reveal which libraries a
  /// user follows (PLAN.md privacy notes).
  @override
  String toString() => 'WatchedLibrary(${identity.rowId})';
}
