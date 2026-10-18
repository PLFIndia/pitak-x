/// The outcome summary of one refresh run (network domain, pure Dart;
/// libNetwork.md §5.6 step 5).
///
/// Lives in its own file because three layers read it (the use case writes
/// it, the controllers carry it, the refresh bar renders it) while only the
/// use case needs the algorithm — and the 500-line file ratchet
/// (architecture.md B8) is a budget, not a target.
library;

/// What one refresh run did (§5.6 step 5). Plain counts + flags — enough for
/// an honest one-line summary; refusal DETAILS stay coarse enums (§6) and
/// never carry response text. [noLongerListed] holds the siteUrls of hubs the
/// user confirmed but whose fetched descriptor no longer lists the user's own
/// fingerprint (the user decides what to do — §5.6 step 4).
final class RefreshReport {
  /// Creates a report.
  const RefreshReport({
    this.fetched = 0,
    this.unreachable = 0,
    this.invalid = 0,
    this.schemaTooNew = 0,
    this.discovered = 0,
    this.truncated = false,
    this.pendingMemberships = 0,
    this.conflicts = 0,
    this.cancelled = false,
    this.noLongerListed = const [],
  });

  /// Descriptors that arrived valid (including ones that then conflicted).
  final int fetched;

  /// Fetches refused for transport-ish reasons (mapped to `unreachable`).
  final int unreachable;

  /// Bodies that did not decode to a valid schema-1 descriptor.
  final int invalid;

  /// Descriptors declaring a newer schema than this build reads.
  final int schemaTooNew;

  /// New rows inserted by discovery this run.
  final int discovered;

  /// True when discovery hit the 500-row cap and stopped early (D10).
  final bool truncated;

  /// Rows newly moved to `MembershipState.pending` (a hub lists me; the UI
  /// prompts).
  final int pendingMemberships;

  /// Rows flagged `identityConflict` this run (D12).
  final int conflicts;

  /// True when the user cancelled mid-run; partial results were still applied.
  final bool cancelled;

  /// SiteUrls of CONFIRMED hubs whose descriptor no longer lists me.
  final List<String> noLongerListed;

  @override
  String toString() =>
      'RefreshReport(ok: $fetched, unreachable: $unreachable, '
      'invalid: $invalid, schemaTooNew: $schemaTooNew, '
      'discovered: $discovered, conflicts: $conflicts, '
      'pending: $pendingMemberships, truncated: $truncated, '
      'cancelled: $cancelled)';
}
