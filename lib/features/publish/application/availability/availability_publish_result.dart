/// Outcomes of one availability-only publish (application layer; ADR 0019
/// Decisions 7, 8 and 10, plan C.4 and A.6 #35).
///
/// The lane (plan S6) turns these into its status row, so each one answers a
/// question the lane must act on:
///  - [AvailabilityGoingLive]: the host accepted the update; save the set as
///    published and, on GitHub, start the deferred check;
///  - [AvailabilityAlreadyPublished]: nothing needed sending; the set is
///    already on the site;
///  - [AvailabilityNotReady]: this site cannot take availability yet (gate
///    7b); wait for a catalogue publish instead of retrying;
///  - [AvailabilityPending]: nothing was changed; keep the set and retry
///    later (AV11: the next change, app resume, the button, or the backoff).
///
/// Host-neutral on purpose: the GitHub path (plan S4) produces all four, and
/// the Cloudflare path (plan S5) adds its own verified outcome here instead of
/// inventing a second result family. The reasons are fixed, safe sentences
/// (AGENTS.md §5): never response text, URLs or exception messages.
library;

import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';

/// Outcome of one availability-only publish.
sealed class AvailabilityPublishResult {
  const AvailabilityPublishResult();
}

/// The host accepted the update; the proof that readers see it is still to
/// come (GitHub: the commit landed, and Pages has not been seen serving it).
final class AvailabilityGoingLive extends AvailabilityPublishResult {
  /// Creates the outcome.
  const AvailabilityGoingLive({
    required this.acceptedAt,
    required this.verification,
    this.localStateSaved = true,
  });

  /// When the host accepted the update, in epoch milliseconds. On GitHub this
  /// is the commit the lane counts towards its spacing and hourly budget
  /// (ADR 0019 Decision 8).
  final int acceptedAt;

  /// What the deferred check must prove, or null when there is nothing it
  /// could upgrade (this phone could not save its record of the commit; the
  /// next publish's pre-check then decides).
  final DeferredVerificationRequest? verification;

  /// False when the update landed but this phone could not save its record of
  /// it (R9). The site IS updated; the next publish reconciles.
  final bool localStateSaved;
}

/// Nothing needed sending: the site already holds exactly this set, or there
/// was no recorded `availability.json` to remove. Nothing was written.
final class AvailabilityAlreadyPublished extends AvailabilityPublishResult {
  /// Creates the outcome.
  const AvailabilityAlreadyPublished();
}

/// This site cannot take availability yet (ADR 0019 Decision 7b): its live
/// catalogue is not this phone's own keyed publish. Nothing was written. A
/// catalogue publish fixes it, so the lane waits instead of retrying.
final class AvailabilityNotReady extends AvailabilityPublishResult {
  /// Creates the outcome with a fixed, safe [reason].
  const AvailabilityNotReady(this.reason);

  /// Why, as a fixed sentence for the status row.
  final String reason;
}

/// Nothing was changed on the site (offline, stale head, credentials, Pages
/// not serving, a contradiction). The lane keeps the set and retries later
/// (AV11); it never retries in a loop and never replaces a site.
final class AvailabilityPending extends AvailabilityPublishResult {
  /// Creates the outcome with a fixed, safe [reason].
  const AvailabilityPending(this.reason);

  /// Why, as a fixed sentence for the status row.
  final String reason;
}

/// Fixed sentences only the availability lane shows (plan C.4 drafts; plan S8
/// sets the final words). Every other reason reuses the host's existing fixed
/// message, so the same failure reads the same everywhere.
abstract final class AvailabilityPublishMessages {
  /// Gate 7b failed: the live `books.json` does not carry this phone's keys.
  static const String catalogueNotKeyed =
      'Publish your catalogue once to turn on automatic availability.';

  /// The branch moved between this phone's read and its commit (R6). Unlike
  /// a manual publish, the lane retries by itself, so the sentence says so.
  static const String siteMovedOn =
      'Another change reached your site first; Pitak will retry.';
}
