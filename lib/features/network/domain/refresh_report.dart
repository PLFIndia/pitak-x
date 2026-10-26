/// The outcome summary of one refresh run (network domain, pure Dart;
/// docs/ARCHITECTURE.md §5.6).
///
/// Lives in its own file because three layers read it (the use case writes
/// it, the controllers carry it, the refresh bar renders it) while only the
/// use case needs the algorithm — and the 500-line file ratchet
/// (file-size ratchet, docs/ARCHITECTURE.md §2.1) is a budget, not a target.
library;

import 'package:pitaka/features/network/domain/library_move_candidate.dart';

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
    this.keptLocalChanges = 0,
    this.moveCandidates = const [],
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

  /// Possible "the same library now lives at this other address" findings
  /// (Cloudflare plan C10/R17). EPHEMERAL: derived from this run's evidence
  /// and never persisted. Each one needs an explicit user decision — nothing
  /// changes automatically, and a declined offer writes nothing.
  final List<LibraryMoveCandidate> moveCandidates;

  /// This report without [candidate] — the controller calls it once the user
  /// has settled that offer, so a stale prompt cannot come back.
  RefreshReport withoutMoveCandidate(LibraryMoveCandidate candidate) =>
      RefreshReport(
        fetched: fetched,
        unreachable: unreachable,
        invalid: invalid,
        schemaTooNew: schemaTooNew,
        discovered: discovered,
        truncated: truncated,
        pendingMemberships: pendingMemberships,
        conflicts: conflicts,
        cancelled: cancelled,
        noLongerListed: noLongerListed,
        keptLocalChanges: keptLocalChanges,
        moveCandidates: [
          for (final c in moveCandidates)
            if (!c.sameAs(candidate)) c,
        ],
      );

  /// Rows whose refresh write was SKIPPED because the user edited them on
  /// this device while the run was fetching (review M1 — the membership
  /// decision or card scan made mid-run always wins; the fetched data
  /// applies on the next run). Surfaced in the summary so the user knows
  /// their edit was kept, not lost.
  final int keptLocalChanges;

  @override
  String toString() =>
      'RefreshReport(ok: $fetched, unreachable: $unreachable, '
      'invalid: $invalid, schemaTooNew: $schemaTooNew, '
      'discovered: $discovered, conflicts: $conflicts, '
      'pending: $pendingMemberships, truncated: $truncated, '
      'cancelled: $cancelled, keptLocal: $keptLocalChanges, '
      'moves: ${moveCandidates.length})';
}
