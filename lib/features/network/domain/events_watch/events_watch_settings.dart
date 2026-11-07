/// The foreground-owned settings document of the background event check
/// (PLAN.md §1, `events_watch_settings.json`).
///
/// Ownership rule (beginner note): ONLY the foreground controller writes
/// this document; the worker only reads it. That is what lets the worker
/// trust "enabled is false" as a definitive stop without any locking.
library;

import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';

/// Immutable settings snapshot.
final class EventsWatchSettings {
  /// Creates settings. Use [EventsWatchSettings.validate] for stored input.
  const EventsWatchSettings({
    required this.enabled,
    required this.token,
    required this.acknowledgedExplanationVersion,
  });

  /// Fresh settings for a brand-new [incarnation]: epoch 0, OFF. The
  /// foreground flips to ON (with a new epoch) only after the user's
  /// first-run offer or an explicit enable succeeds.
  factory EventsWatchSettings.initial(String incarnation) =>
      EventsWatchSettings(
        enabled: false,
        token: WatchSettingsToken(incarnation: incarnation, epoch: 0),
        acknowledgedExplanationVersion: 0,
      );

  /// Schema this build reads and writes.
  static const int schemaVersion = 1;

  /// Version of the pre-permission explanation the user has seen; the
  /// explanation is shown again only when this build's version is higher.
  static const int currentExplanationVersion = 1;

  /// Whether the user wants background checks.
  final bool enabled;

  /// Identity of the current enabled period (see [WatchSettingsToken]).
  final WatchSettingsToken token;

  /// Highest explanation version acknowledged; 0 = never shown.
  final int acknowledgedExplanationVersion;

  /// Fresh settings for a brand-new [incarnation]: epoch 0, OFF. The
  /// foreground flips to ON (with a new epoch) only after the user's
  /// first-run offer or an explicit enable succeeds.

  /// Strict ingress gate for decoded documents. Null = unreadable.
  static EventsWatchSettings? validate({
    required Object? enabled,
    required Object? incarnation,
    required Object? epoch,
    required Object? acknowledgedExplanationVersion,
  }) {
    if (enabled is! bool) return null;
    final token = WatchSettingsToken.validate(
      incarnation: incarnation,
      epoch: epoch,
    );
    if (token == null) return null;
    if (acknowledgedExplanationVersion is! int ||
        acknowledgedExplanationVersion < 0 ||
        acknowledgedExplanationVersion > 1000) {
      return null;
    }
    return EventsWatchSettings(
      enabled: enabled,
      token: token,
      acknowledgedExplanationVersion: acknowledgedExplanationVersion,
    );
  }

  /// The settings after an explicit enable/disable: a NEW epoch every time,
  /// even when [enabled] does not change (the user's intent is new).
  EventsWatchSettings withEnabled({required bool enabled}) =>
      EventsWatchSettings(
        enabled: enabled,
        token: token.nextEpoch(),
        acknowledgedExplanationVersion: acknowledgedExplanationVersion,
      );

  /// The settings after the explanation dialog was acknowledged.
  EventsWatchSettings withExplanationAcknowledged() => EventsWatchSettings(
    enabled: enabled,
    token: token,
    acknowledgedExplanationVersion: currentExplanationVersion,
  );

  /// True when this build's explanation must be shown before prompting.
  bool get needsExplanation =>
      acknowledgedExplanationVersion < currentExplanationVersion;

  /// Field-by-field equality (repo convention).
  bool sameAs(EventsWatchSettings other) =>
      other.enabled == enabled &&
      other.token.sameAs(token) &&
      other.acknowledgedExplanationVersion == acknowledgedExplanationVersion;

  @override
  String toString() => 'EventsWatchSettings(enabled: $enabled, $token)';
}
