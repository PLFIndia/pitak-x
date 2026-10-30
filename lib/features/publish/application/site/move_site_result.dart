/// Secret-free move confirmations, progress, and truthful operation outcomes.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';

/// The exact complete snapshot and endpoints the user reviewed.
final class MoveSiteConfirmation {
  /// Creates a safe confirmation projection with no snapshot bytes or secrets.
  const MoveSiteConfirmation({
    required this.oldTarget,
    required this.newTarget,
    required this.sourceAnchor,
    required this.digest,
    required this.catalogueItemCount,
    required this.posterCount,
    required this.availabilityOmitted,
    this.destinationWarning,
    this.destinationAnchor,
    this.replacesDestinationContent = false,
  });

  /// Exact current site that will later be retired.
  final PublishTarget oldTarget;

  /// Exact destination whose descriptor and content are reviewed.
  final PublishTarget newTarget;

  /// Source identity that must remain unchanged through destination writing.
  final MoveSourceAnchor sourceAnchor;

  /// Canonical R4 digest of the complete destination snapshot.
  final String digest;

  /// Live catalogue rows in the reviewed snapshot.
  final int catalogueItemCount;

  /// Event posters in the reviewed snapshot.
  final int posterCount;

  /// Whether vault locking omitted availability from the reviewed snapshot.
  final bool availabilityOmitted;

  /// One fixed, safe sentence about the destination that the user must see
  /// before confirming (for example "the Worker no longer exists").
  ///
  /// Null for an ordinary destination. It never carries response text.
  final String? destinationWarning;

  /// The destination facts the user reviewed when the destination held content
  /// this phone did not publish (fix-plan L16).
  ///
  /// Publish re-reads the destination and re-prompts when this no longer
  /// matches, so one review authorises exactly one observed state.
  final CloudflareRemoteAnchor? destinationAnchor;

  /// True when confirming replaces content the user did not publish here, so
  /// the dialog's action says "Replace and move" instead of "Move library".
  final bool replacesDestinationContent;

  /// The same review with an extra destination sentence.
  MoveSiteConfirmation withDestinationWarning(String warning) =>
      _copy(destinationWarning: warning);

  /// The same review with an explicit replacement consent for [anchor].
  ///
  /// Used when the destination is in an `unknown` state: its content is real
  /// (a setup check, another device, or a foreign marker) and a move deletes
  /// it, so the user must see that before confirming (F.5 step 2).
  MoveSiteConfirmation withDestinationConsent({
    required CloudflareRemoteAnchor anchor,
    required String warning,
  }) => _copy(
    destinationWarning: warning,
    destinationAnchor: anchor,
    replacesDestinationContent: true,
  );

  MoveSiteConfirmation _copy({
    String? destinationWarning,
    CloudflareRemoteAnchor? destinationAnchor,
    bool? replacesDestinationContent,
  }) => MoveSiteConfirmation(
    oldTarget: oldTarget,
    newTarget: newTarget,
    sourceAnchor: sourceAnchor,
    digest: digest,
    catalogueItemCount: catalogueItemCount,
    posterCount: posterCount,
    availabilityOmitted: availabilityOmitted,
    destinationWarning: destinationWarning ?? this.destinationWarning,
    destinationAnchor: destinationAnchor ?? this.destinationAnchor,
    replacesDestinationContent:
        replacesDestinationContent ?? this.replacesDestinationContent,
  );

  /// True when the reviewed catalogue has no items.
  bool get catalogueIsEmpty => catalogueItemCount == 0;

  /// True when the reviewed events page has no posters.
  bool get eventsIsEmpty => posterCount == 0;

  /// Binds a confirmation re-entry to the same two sealed endpoints.
  bool hasTargets(PublishTarget old, PublishTarget replacement) =>
      oldTarget.isSameExactTarget(old) &&
      newTarget.isSameExactTarget(replacement);
}

/// Coarse D.4 progress labels. No credential or response data is attached.
enum MoveSitePhase {
  /// Reading and validating the strict complete snapshot.
  preparingSnapshot,

  /// Checking source and destination anchors.
  checkingSites,

  /// Writing the destination snapshot.
  publishingDestination,

  /// Proving the complete destination through exact-origin read-back.
  verifyingDestination,

  /// Persisting the pending journal without switching the share target.
  recordingMove,

  /// Writing the moved page to the exact old target.
  updatingOldAddress,

  /// Proving the moved page and old-content removal.
  verifyingOldAddress,

  /// Proving a GitHub Pages moved page, which may still be building.
  verifyingOldAddressGitHubPages,
}

/// Outcome of an outer move, Retry, or Skip command.
sealed class MoveSiteResult {
  /// Base type for sealed move outcomes.
  const MoveSiteResult();
}

/// Local content or remote anchors changed; the user must review this version.
final class MoveSiteConfirmationRequired extends MoveSiteResult {
  /// Creates a review outcome.
  const MoveSiteConfirmationRequired(this.confirmation);

  /// Fresh content and endpoints requiring confirmation.
  final MoveSiteConfirmation confirmation;
}

/// The command stopped at a safe boundary.
final class MoveSiteFailure extends MoveSiteResult {
  /// Creates a fixed, safe failure outcome.
  const MoveSiteFailure(
    this.reason, {
    this.retirementPending = false,
    this.destinationLocalStateSaved = true,
    this.canFinishWithoutRetiring = false,
    this.oldSiteAnswers = false,
  });

  /// Fixed safe copy; never a raw response or platform exception.
  final String reason;

  /// True when the journal retains a destination-verified pending move.
  final bool retirementPending;

  /// False discloses a destination local-commit failure without pretending the
  /// destination was not verified.
  final bool destinationLocalStateSaved;

  /// True only when the Skip check proved Pitak cannot sign in to the old
  /// site, so "Finish without retiring" is the honest next step (fix-plan M4).
  final bool canFinishWithoutRetiring;

  /// Whether the old public address still answers; selects the finish copy.
  final bool oldSiteAnswers;
}

/// The pending move was cancelled; both sites are untouched (fix-plan M4).
final class MoveSiteAbandoned extends MoveSiteResult {
  /// Creates a cancelled-move outcome.
  const MoveSiteAbandoned({required this.oldTarget, required this.newTarget});

  /// The site the user keeps publishing to and sharing.
  final PublishTarget oldTarget;

  /// The already-published copy that stays online until the user deletes it.
  final PublishTarget newTarget;
}

/// The verified destination is selected and pending history is cleared.
final class MoveSiteSuccess extends MoveSiteResult {
  /// Creates a completed or explicitly skipped move outcome.
  const MoveSiteSuccess({
    required this.target,
    this.retirementSkipped = false,
    this.localStateSaved = true,
    this.temporaryCleanupFailed = false,
  });

  /// Verified destination now used for publishing and sharing.
  final PublishTarget target;

  /// Explicit Skip only; never displayed as successful source retirement.
  final bool retirementSkipped;

  /// Whether all required local destination state was committed.
  final bool localStateSaved;

  /// Whether temporary public artifact cleanup also reported a failure.
  final bool temporaryCleanupFailed;
}

/// Result from one host's complete destination publisher.
sealed class MoveDestinationResult {
  /// Base type for sealed destination outcomes.
  const MoveDestinationResult();
}

/// The complete destination passed every required public read-back.
final class MoveDestinationPublished extends MoveDestinationResult {
  /// Creates a verified destination outcome.
  const MoveDestinationPublished({
    this.localStateSaved = true,
    this.temporaryCleanupFailed = false,
  });

  /// Whether the destination manifest and related local state were saved.
  final bool localStateSaved;

  /// Whether operation-scoped public artifact cleanup failed separately.
  final bool temporaryCleanupFailed;
}

/// Rebuilding found different content; no stale destination write was allowed.
final class MoveDestinationConfirmationRequired extends MoveDestinationResult {
  /// Creates a fresh-review outcome.
  const MoveDestinationConfirmationRequired(this.confirmation);

  /// Newly rebuilt confirmation to show instead of deploying stale content.
  final MoveSiteConfirmation confirmation;
}

/// Destination publication stopped before pending-state creation.
final class MoveDestinationFailed extends MoveDestinationResult {
  /// Creates a fixed, safe destination failure.
  const MoveDestinationFailed(this.reason, {this.localStateSaved = true});

  /// Safe user-facing reason with no transport or credential details.
  final String reason;

  /// False when the destination's public record could not be saved on this
  /// phone, so the failure copy says the site may be live but unrecorded
  /// (fix-plan L12).
  final bool localStateSaved;
}

/// Successful source retirement, including any separate spool cleanup truth.
final class SiteRetirementOutcome {
  /// Creates a retirement outcome.
  const SiteRetirementOutcome({this.temporaryCleanupFailed = false});

  /// Whether temporary public artifact cleanup failed after retirement.
  final bool temporaryCleanupFailed;
}

/// Fixed copy shared by move orchestration and presentation.
abstract final class MoveSiteMessages {
  /// A second move may not replace existing recovery history.
  static const String pendingAlreadyExists =
      'Finish, skip or cancel the pending move before starting another one.';

  /// Both sealed endpoints and their address proofs are required.
  static const String setupRequired =
      'Connect and verify both publishing targets before moving.';

  /// Confirmation or configuration no longer matches current state.
  static const String stale =
      'The publishing state changed. Review the move again before continuing.';

  /// The source anchor changed, so retirement is forbidden.
  static const String sourceChanged =
      'The current site changed during the move. It was not retired.';

  /// Reconnected credentials no longer identify the recorded endpoint.
  static const String targetMismatch =
      'Reconnect the exact publishing target used by this move.';

  /// The moved-page name could not be read; nothing was published or moved.
  static const String settingsUnavailable =
      'Library settings could not be read. Nothing was moved.';

  /// The moved page could not be built for this library name, so the move
  /// stopped before any write (fix-plan M9).
  static const String movedPageNotPrepared =
      'The moved page for your old address could not be prepared. Nothing was '
      'changed.';

  /// The source is absent or cannot be read reliably enough to retire.
  static const String sourceUnavailable =
      'The current site is unavailable or its publishing state is unreadable.';

  /// The DESTINATION moved after review; the source is untouched.
  ///
  /// Reporting this as "source changed" named the wrong site and sent the user
  /// to fix a site that had not changed (fix-plan N5).
  static const String destinationChanged =
      'The Cloudflare site changed while the move was being prepared. Nothing '
      'was published.';

  /// The destination is live but this phone could not record it.
  static const String localRecordNotSaved =
      'This phone could not save its record of the new site.';

  /// Skip is not authorization to hide a reachable or changed old site.
  static const String skipNotAllowed =
      'Skip is available only when the old repository or Worker no longer '
      'exists.';

  /// The old site cannot be signed in to, so it can be neither checked nor
  /// retired. The UI offers "Finish without retiring" (fix-plan M4).
  static const String sourceInaccessible =
      'Pitak cannot sign in to the old site, so it cannot check or retire it. '
      'Reconnect it and choose Retry move. If you no longer have access, you '
      'can finish the move without retiring the old site.';

  /// The Skip check itself failed; nothing is proven either way.
  static const String sourceCheckFailed =
      'Pitak could not check the old site. Try again when you are online.';

  /// Cancel is refused once the old address already shows the moved page.
  static const String cancelAfterRetirement =
      'Your old address already shows the moved page. Choose Retry move to '
      'finish moving.';

  /// Cancel succeeded; both sites are untouched.
  static String moveCancelled(String oldAddress, String newAddress) =>
      'Move cancelled. Your site is still $oldAddress. The copy at '
      '$newAddress stays online until you delete it.';

  /// Finish-without-retiring is refused when the old site is still reachable.
  static const String finishNotAllowed =
      'The old site can still be reached, so the move cannot finish without '
      'retiring it. Choose Retry move.';

  /// Complete destination read-back did not pass. The new host may simply
  /// still be building (GitHub Pages can take minutes), so suggest a later
  /// retry; never claim the new site is absent or the move impossible.
  static const String destinationNotVerified =
      'The new site could not be verified yet. The current site was not '
      'changed. Try the move again in a few minutes.';

  /// Destination proof exists, but the pending journal could not be saved.
  static const String pendingSaveFailed =
      'The new site is verified, but the move could not be recorded. '
      'The current site was not retired.';

  /// Pending source retirement needs an idempotent retry.
  static const String retirementFailed =
      'The old address could not be retired. Retry the pending move.';

  /// Retirement is done, but the final journal switch still needs retry.
  static const String completionFailed =
      'Retirement finished, but the move could not be completed on this phone. '
      'Retry to finish it.';

  /// The destination Worker was deleted; the move recreates it completely.
  static String workerMissingDestination(String address) =>
      'The Worker for $address no longer exists. Pitak creates it with your '
      'whole library.';

  /// The destination Worker already holds content this phone did not publish.
  ///
  /// This is the NORMAL first move into Cloudflare (a setup check, another
  /// device, or a foreign marker), so it is a consent line rather than an
  /// error (fix-plan L16).
  static String unknownDestination(String workerName) =>
      'The Cloudflare Worker "$workerName" already has content this phone did '
      'not publish (for example a setup check or another device). Moving '
      'replaces everything on that Worker.';

  /// Unexpected failures are collapsed to fixed copy without remote details.
  static const String generic =
      'The move could not be completed. No unverified address was selected.';
}
