/// Outcome types for one catalogue publish run (application layer).
///
/// Kept separate from the orchestrator so the public result contract stays
/// small and readable while publish preparation gains explicit validation.
library;

import 'package:pitaka/features/publish/domain/publish_target.dart';

/// Outcome of a publish.
sealed class PublishResult {
  const PublishResult();
}

/// The ordinary section a user asked to publish.
enum PublishRequestedSection {
  /// Catalogue only; an existing events section is preserved.
  catalogue,

  /// Events only; the catalogue is preserved.
  events,
}

/// Safe, non-artifact state needed to confirm a whole-Worker replacement.
///
/// No local entities, snapshot bytes, credentials, or upload tokens cross into
/// controller/UI state. The digest binds this summary to the exact logical
/// content the user reviewed; target and requested section bind the operation.
final class PublishReplacementSummary {
  /// Creates a confirmation summary from a validated complete snapshot.
  const PublishReplacementSummary({
    required this.target,
    required this.requestedSection,
    required this.digest,
    required this.catalogueItemCount,
    required this.posterCount,
    required this.availabilityOmitted,
  });

  /// Exact Cloudflare Worker being replaced.
  final CloudflarePublishTarget target;

  /// Button that initiated reconciliation (replacement itself covers both).
  final PublishRequestedSection requestedSection;

  /// Canonical R4 content digest, excluding operation timestamps and ids.
  final String digest;

  /// Live catalogue rows in the reviewed snapshot.
  final int catalogueItemCount;

  /// Event posters in the reviewed snapshot.
  final int posterCount;

  /// Whether availability was omitted because the vault was locked.
  final bool availabilityOmitted;

  /// True when the reviewed catalogue has no items.
  bool get catalogueIsEmpty => catalogueItemCount == 0;

  /// True when the reviewed events page has no posters.
  bool get eventsIsEmpty => posterCount == 0;
}

/// Unknown or retired remote state requires explicit whole-site replacement.
final class PublishReplacementRequired extends PublishResult {
  /// Creates a typed, expected confirmation outcome (not an error).
  const PublishReplacementRequired(this.summary);

  /// The exact content and target the user must review.
  final PublishReplacementSummary summary;
}

/// Publish succeeded.
final class PublishSuccess extends PublishResult {
  /// Creates a success result.
  const PublishSuccess({
    required this.pagesUrl,
    required this.uploadedPaths,
    this.availabilityOmitted = false,
    this.pagesLive,
    this.localStateSaved = true,
    this.temporaryCleanupFailed = false,
  });

  /// The public page URL.
  final String pagesUrl;

  /// Files whose bytes were uploaded this run.
  final List<String> uploadedPaths;

  /// True when availability was omitted (vault locked at publish).
  final bool availabilityOmitted;

  /// True when the live site was VERIFIED serving this publish's bytes
  /// (read-back, à la Localcart Orange); null when the bounded wait ran out
  /// before the Pages build landed (it usually finishes moments later).
  final bool? pagesLive;

  /// False when the commit landed but this phone could not save its own record
  /// of the publish (R9).
  ///
  /// The site IS updated — the honest message says exactly that — and the next
  /// publish re-reads the remote tree, so the lost record costs one
  /// reconciliation, not correctness.
  final bool localStateSaved;

  /// True when public temporary artifacts could not be removed after the run.
  /// This never means the remote publish failed; the UI reports it separately.
  final bool temporaryCleanupFailed;
}

/// Publish failed; [reason] is a safe, human-readable message.
final class PublishFailure extends PublishResult {
  /// Creates a failure result.
  const PublishFailure(this.reason);

  /// Why it failed.
  final String reason;
}
