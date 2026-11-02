/// Outcomes of one availability-only publish (application layer; ADR 0019
/// Decisions 7, 8 and 10, plan C.4 and A.6 #35).
///
/// The lane (plan S6) turns these into its status row, so each one answers a
/// question the lane must act on:
///  - [AvailabilityLive]: the host accepted the update and the live site was
///    read back serving it; save the set as published, nothing is left to
///    prove (Cloudflare);
///  - [AvailabilityGoingLive]: the host accepted the update, not yet proven
///    live; save the set as published and, on GitHub, start the deferred
///    check;
///  - [AvailabilityAlreadyPublished]: nothing needed sending; the set is
///    already on the site;
///  - [AvailabilityNotReady]: this site cannot take availability yet (gate
///    7b); wait for a catalogue publish instead of retrying;
///  - [AvailabilityPending]: nothing was changed, or the change is not known
///    to be live; keep the set and retry later (AV11: the next change, app
///    resume, the button, or the backoff).
///
/// Host-neutral on purpose: the GitHub path (plan S4) produces the last four,
/// and the Cloudflare path (plan S5) produces all five; there is no second
/// result family. The reasons are fixed, safe sentences (AGENTS.md §5):
/// never response text, URLs or exception messages.
library;

import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';

/// Outcome of one availability-only publish.
sealed class AvailabilityPublishResult {
  const AvailabilityPublishResult();
}

/// The host accepted the update AND the live site was read back serving it:
/// on Cloudflare, the fresh marker plus `availability.json` (or its exact 404
/// after a removal; ADR 0019 Decision 11). Nothing is left to prove.
final class AvailabilityLive extends AvailabilityPublishResult {
  /// Creates the outcome.
  const AvailabilityLive({
    required this.acceptedAt,
    this.localStateSaved = true,
  });

  /// When the update was made, in epoch milliseconds (the deploy's marker
  /// time). Cloudflare has no hourly budget (AV6), so this is informational.
  final int acceptedAt;

  /// False when the site was proven live but this phone could not save all
  /// of that proof (R9). The site IS updated; the next publish re-proves it.
  final bool localStateSaved;
}

/// The host accepted the update; the proof that readers see it is still to
/// come (GitHub: the commit landed, and Pages has not been seen serving it;
/// Cloudflare: the version was deployed, and its read-back ran out of budget
/// before it saw the new files).
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

  /// What the deferred check must prove, or null when there is nothing for
  /// one to do: this phone could not save its record of the commit, or the
  /// host has no deferred check (Cloudflare). The next publish's pre-check
  /// then decides (on Cloudflare, its existing-publication check reads the
  /// `deployed` record back).
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
  const AvailabilityNotReady(this.reason, {this.staleFileRecorded = false});

  /// Why, as a fixed sentence for the status row.
  final String reason;

  /// True when this phone's record still shows an `availability.json` on the
  /// site although the live catalogue no longer carries this phone's keys
  /// (another writer replaced `books.json`, or a restore cleared the flag;
  /// plan J9). Its keys may then match nothing, which shows every item as
  /// Available — the dangerous direction — so the lane publishes the removal
  /// at once (plan S6; a removal needs no gate 7b, A.6 #47).
  final bool staleFileRecorded;
}

/// Nothing was changed on the site (offline, stale head, credentials, Pages
/// not serving, a contradiction, a site that needs repair), or a change is
/// not known to be live (a Cloudflare deploy whose outcome or Version-URL
/// privacy could not be confirmed; the reason says so). The lane keeps the
/// set and retries later (AV11); it never retries in a loop and never
/// replaces a site. A retry first re-proves an earlier deploy, so a set that
/// did land then reads as [AvailabilityAlreadyPublished].
final class AvailabilityPending extends AvailabilityPublishResult {
  /// Creates the outcome with a fixed, safe [reason].
  const AvailabilityPending(this.reason);

  /// Why, as a fixed sentence for the status row.
  final String reason;

  /// True when only the user can fix this: the site needs the reviewed repair
  /// that Publish to web offers ([AvailabilityPublishMessages.repairSite]).
  /// The lane still retries (AV11), but at its slowest pace (plan S6).
  bool get needsRepair => reason == AvailabilityPublishMessages.repairSite;
}

/// Fixed sentences only the availability lane shows (final words since plan
/// S8, A.6 #80). Every other reason reuses the host's existing fixed
/// message, so the same failure reads the same everywhere. They appear in
/// the Availability card right under the Publish card, so they name its
/// button, **Publish catalogue now**.
abstract final class AvailabilityPublishMessages {
  /// Gate 7b failed: the live `books.json` does not carry this phone's keys.
  static const String catalogueNotKeyed =
      'Tap Publish catalogue now once; after that, availability updates by '
      'itself.';

  /// The branch moved between this phone's read and its commit (R6). Unlike
  /// a manual publish, the lane retries by itself, so the sentence says so.
  static const String siteMovedOn =
      'Another change reached your site first; Pitak will retry.';

  /// The live site is not the one this phone's record describes, or a deploy
  /// would need bytes this phone no longer has (Cloudflare: a foreign,
  /// unknown or retired marker, a missing Worker, a contradicted record,
  /// missing bytes). Only a whole-site replacement can fix that, and that
  /// needs the user's review (ADR 0017 S8), so the lane never starts one
  /// (ADR 0019 Decision 11): it points the user to the screen that offers it.
  static const String repairSite =
      'Your site needs a full publish: tap Publish catalogue now and review '
      'the replacement.';
}
