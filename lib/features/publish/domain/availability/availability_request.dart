/// What one publish does with `availability.json` (publish domain, pure Dart;
/// ADR 0019 Decision 6, plan AV4/AV8 and A.6 #20).
///
/// Why a request and not a flag (beginner note): a publish can do exactly two
/// things with the availability file, and each has its own safety rule:
///  - the lane is ON: write the "not available" set, but only from loan counts
///    that are actually known. A locked vault leaves the live file exactly as
///    it is, because "unknown" must never become "everything is available";
///  - the lane is OFF: delete the file when this phone's record shows it, so
///    readers fall back to the inline tag instead of a file that has silently
///    stopped updating.
///
/// The request is read once per operation through `PublishReads`, on the same
/// strict path as the library and the settings, so every flow that builds a
/// snapshot (catalogue, events, moves, replacements) follows the same rule.
library;

/// The availability part of one publish.
///
/// A sealed class (rather than an enum) so a later session can attach data to
/// one case — for example a saved snapshot for a move made while the vault is
/// locked (plan AV18) — without changing how callers switch over it.
sealed class AvailabilityRequest {
  const AvailabilityRequest();
}

/// The lane is on: publish the set computed from THIS publish's own loan
/// counts (plan AV8).
///
/// Using the very counts the inline `books.json` tag is built from is what
/// keeps the two sources in agreement on a freshly published site. When the
/// counts are unknown (vault locked), or the publish builds no catalogue, the
/// live `availability.json` is left untouched.
final class AvailabilityFromLoanCounts extends AvailabilityRequest {
  /// Creates the request.
  const AvailabilityFromLoanCounts();

  @override
  String toString() => 'AvailabilityFromLoanCounts()';
}

/// The lane is off: delete `availability.json` if this phone's record shows
/// it (plan AV4, A.6 #20). With no recorded file there is nothing to do.
final class AvailabilityRemoval extends AvailabilityRequest {
  /// Creates the request.
  const AvailabilityRemoval();

  @override
  String toString() => 'AvailabilityRemoval()';
}
