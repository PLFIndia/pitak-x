/// Coarse, safe progress for the restore dialog (no URLs or remote text).
library;

/// Restore phases; cancellation is disabled during [writing].
enum RestoreFromPublishedSitePhase {
  /// Reading identity and catalogue bytes.
  reading,

  /// Downloading same-site covers.
  covers,

  /// Committing the catalogue and recovering identity.
  writing,
}

/// One progress snapshot.
final class RestoreFromPublishedSiteProgress {
  /// Creates a progress snapshot.
  const RestoreFromPublishedSiteProgress(
    this.phase, {
    this.completed = 0,
    this.total = 0,
  });

  /// Current phase.
  final RestoreFromPublishedSitePhase phase;

  /// Completed cover count (zero in other phases).
  final int completed;

  /// Total distinct same-site covers (zero in other phases).
  final int total;
}

/// Receives safe progress snapshots without remote text.
typedef RestoreFromPublishedSiteProgressCallback =
    void Function(RestoreFromPublishedSiteProgress progress);
