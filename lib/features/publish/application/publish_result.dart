/// Outcome types for one catalogue publish run (application layer).
///
/// Kept separate from the orchestrator so the public result contract stays
/// small and readable while publish preparation gains explicit validation.
library;

/// Outcome of a publish.
sealed class PublishResult {
  const PublishResult();
}

/// Publish succeeded.
final class PublishSuccess extends PublishResult {
  /// Creates a success result.
  const PublishSuccess({
    required this.pagesUrl,
    required this.uploadedPaths,
    this.availabilityOmitted = false,
    this.pagesLive,
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
}

/// Publish failed; [reason] is a safe, human-readable message.
final class PublishFailure extends PublishResult {
  /// Creates a failure result.
  const PublishFailure(this.reason);

  /// Why it failed.
  final String reason;
}
