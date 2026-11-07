/// Typed result of one background run (PLAN.md Step 2: "returns a typed
/// run report"). The dispatcher maps it to WorkManager's success/retry.
library;

/// Why a run ended without (or before) doing ordinary work.
enum WatchRunStop {
  /// Settings say OFF.
  disabled,

  /// No settings file: only the foreground may create defaults.
  settingsMissing,

  /// Settings corrupt or from a newer build: fail closed.
  settingsUnreadable,

  /// State file from a newer build: never overwritten, nothing done.
  stateNewerSchema,

  /// State file was unreadable and replaced by a recovery document; no
  /// fetch this run.
  recovered,

  /// A revocation marker for the current token exists, or permission was
  /// found blocked this run and the marker was written.
  revoked,

  /// No trustworthy active data generation.
  noGeneration,

  /// More saved libraries than the hard cap.
  capacityExceeded,

  /// No saved libraries; the job was cancelled.
  noLibraries,

  /// Settings token changed mid-run; remaining work abandoned.
  tokenChanged,

  /// Data generation changed mid-run; remaining work abandoned.
  generationChanged,

  /// Safety deadline reached; remaining work abandoned.
  deadline,
}

/// Immutable summary of one run.
final class WatchRunReport {
  /// Creates a report.
  const WatchRunReport({
    required this.requestRetry,
    required this.stop,
    required this.checked,
    required this.withheld,
    required this.failed,
    required this.librariesNotified,
  });

  /// A report for an early stop with no site work.
  const WatchRunReport.stopped(WatchRunStop reason, {bool retry = false})
    : this(
        requestRetry: retry,
        stop: reason,
        checked: 0,
        withheld: 0,
        failed: 0,
        librariesNotified: 0,
      );

  /// A report for an infrastructure failure before any site work.
  const WatchRunReport.retry()
    : this(
        requestRetry: true,
        stop: null,
        checked: 0,
        withheld: 0,
        failed: 0,
        librariesNotified: 0,
      );

  /// True when an infrastructure failure means WorkManager should retry
  /// with backoff; false for every expected outcome.
  final bool requestRetry;

  /// Early-stop reason, or null when the run did its ordinary work.
  final WatchRunStop? stop;

  /// Sites with an authoritative read.
  final int checked;

  /// Sites whose payload could not be diffed.
  final int withheld;

  /// Sites whose fetch failed.
  final int failed;

  /// Libraries whose alert was submitted this run.
  final int librariesNotified;

  @override
  String toString() =>
      'WatchRunReport(retry: $requestRetry, stop: ${stop?.name}, '
      'checked: $checked, withheld: $withheld, failed: $failed, '
      'notified: $librariesNotified)';
}
