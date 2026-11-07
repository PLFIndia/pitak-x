/// Per-library bookkeeping of the background event check (PLAN.md §1
/// "Site status").
library;

import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// Coarse result of the last completed attempt at one site. Safe to show
/// as a count in Settings; never carries a URL or status text.
enum SiteCheckOutcome {
  /// No attempt completed yet.
  never,

  /// Authoritative read (`200`, validated `304`, or `404`).
  ok,

  /// The file was served but this build could not diff it (partial read,
  /// duplicate reference, newer schema). Alerts for this site are withheld.
  withheld,

  /// Transport/decode failure; nothing changed.
  failed,
}

/// Immutable status of one watched library.
final class SiteWatchStatus {
  /// Creates a status. Use [validate] for stored input.
  const SiteWatchStatus({
    required this.identity,
    required this.notificationId,
    required this.lastAttemptAt,
    required this.lastSuccessfulCheckAt,
    required this.lastOutcome,
    required this.baseline,
  });

  /// A fresh status for a row the worker sees for the first time.
  factory SiteWatchStatus.fresh(WatchedLibraryIdentity identity) =>
      SiteWatchStatus(
        identity: identity,
        notificationId: null,
        lastAttemptAt: null,
        lastSuccessfulCheckAt: null,
        lastOutcome: SiteCheckOutcome.never,
        baseline: null,
      );

  /// The saved row this status tracks.
  final WatchedLibraryIdentity identity;

  /// Stable Android notification id allocated for this library, or null
  /// until the first submission. Persisted so retries reuse it.
  final int? notificationId;

  /// Epoch millis of the last completed attempt (success or failure).
  final int? lastAttemptAt;

  /// Epoch millis of the last authoritative read, or null.
  final int? lastSuccessfulCheckAt;

  /// Outcome of the last completed attempt.
  final SiteCheckOutcome lastOutcome;

  /// Last authoritative content, or null before the first one.
  final SiteBaseline? baseline;

  /// Convenience: canonical site URL.
  String get siteUrl => identity.siteUrl;

  /// A fresh status for a row the worker sees for the first time.

  /// Strict gate for stored scalars (identity and baseline are validated
  /// by their own gates before being passed in).
  static SiteWatchStatus? validate({
    required WatchedLibraryIdentity identity,
    required Object? notificationId,
    required Object? lastAttemptAt,
    required Object? lastSuccessfulCheckAt,
    required Object? lastOutcome,
    required SiteBaseline? baseline,
  }) {
    if (notificationId != null &&
        (notificationId is! int ||
            notificationId <= 0 ||
            notificationId > 0x7fffffff)) {
      return null;
    }
    if (!_isNullableNonNegativeInt(lastAttemptAt) ||
        !_isNullableNonNegativeInt(lastSuccessfulCheckAt)) {
      return null;
    }
    final outcome = switch (lastOutcome) {
      'never' => SiteCheckOutcome.never,
      'ok' => SiteCheckOutcome.ok,
      'withheld' => SiteCheckOutcome.withheld,
      'failed' => SiteCheckOutcome.failed,
      _ => null,
    };
    if (outcome == null) return null;
    return SiteWatchStatus(
      identity: identity,
      notificationId: notificationId as int?,
      lastAttemptAt: lastAttemptAt as int?,
      lastSuccessfulCheckAt: lastSuccessfulCheckAt as int?,
      lastOutcome: outcome,
      baseline: baseline,
    );
  }

  static bool _isNullableNonNegativeInt(Object? value) =>
      value == null || (value is int && value >= 0);

  /// Copy with selected fields replaced. `clearBaseline` exists because a
  /// null argument cannot distinguish "keep" from "set to null".
  SiteWatchStatus copyWith({
    int? notificationId,
    int? lastAttemptAt,
    int? lastSuccessfulCheckAt,
    SiteCheckOutcome? lastOutcome,
    SiteBaseline? baseline,
    bool clearBaseline = false,
  }) => SiteWatchStatus(
    identity: identity,
    notificationId: notificationId ?? this.notificationId,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastSuccessfulCheckAt: lastSuccessfulCheckAt ?? this.lastSuccessfulCheckAt,
    lastOutcome: lastOutcome ?? this.lastOutcome,
    baseline: clearBaseline ? null : (baseline ?? this.baseline),
  );

  @override
  String toString() =>
      'SiteWatchStatus(#${identity.rowId}, ${lastOutcome.name})';
}
