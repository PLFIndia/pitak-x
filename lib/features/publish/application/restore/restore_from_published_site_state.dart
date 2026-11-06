/// Immutable UI state for the keep-alive restore controller.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';

/// Controller lifecycle states.
enum RestoreFromPublishedSiteStatus {
  /// No operation or terminal result.
  idle,

  /// An operation is in flight.
  running,

  /// The catalogue committed.
  success,

  /// The user cancelled before writing.
  cancelled,

  /// A typed failure occurred.
  error,
}

/// Immutable restore UI state.
final class RestoreFromPublishedSiteState {
  /// Creates a state snapshot.
  const RestoreFromPublishedSiteState({
    required this.status,
    this.progress = const RestoreFromPublishedSiteProgress(
      RestoreFromPublishedSitePhase.reading,
    ),
    this.summary,
    this.failure,
  });

  /// Creates the idle state.
  const RestoreFromPublishedSiteState.idle()
    : this(status: RestoreFromPublishedSiteStatus.idle);

  /// Current lifecycle state.
  final RestoreFromPublishedSiteStatus status;

  /// Latest safe progress snapshot.
  final RestoreFromPublishedSiteProgress progress;

  /// Committed summary, retained across navigation.
  final RestoreFromPublishedSiteSummary? summary;

  /// Typed terminal failure, when present.
  final Failure? failure;

  /// Whether an operation is in flight.
  bool get isRunning => status == RestoreFromPublishedSiteStatus.running;

  /// Cancellation is available only before the writing phase.
  bool get canCancel =>
      isRunning && progress.phase != RestoreFromPublishedSitePhase.writing;

  /// Returns a running state with [next] progress.
  RestoreFromPublishedSiteState running(
    RestoreFromPublishedSiteProgress next,
  ) => RestoreFromPublishedSiteState(
    status: RestoreFromPublishedSiteStatus.running,
    progress: next,
  );
}
