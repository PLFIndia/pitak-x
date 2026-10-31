/// The per-run state machine behind `RefreshNetworkUseCase` (network domain,
/// pure Dart; docs/ARCHITECTURE.md §5.6). See the use case for the contract.
///
/// Why this file exists: the algorithm plus the C10/R17 move offer crossed the
/// 500-line ratchet in one file, and the plan (R29) forbids a new allow-list
/// entry. Nothing here is used by any other file.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/library_move_candidate.dart';
import 'package:pitaka/features/network/domain/network_discovery_plan.dart';
import 'package:pitaka/features/network/domain/refresh_report.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// The mutable state of ONE refresh run.
///
/// Split out of `refresh_network_use_case.dart` when the C10/R17 move offer
/// pushed that file past the 500-line ratchet (AGENTS §11, plan R29). It is
/// PUBLIC only because Dart privacy is library-scoped: `RefreshNetworkUseCase`
/// is the sole caller, and nothing else in the app imports this file.
final class RefreshRun {
  /// Creates one run over its ports. [ownFingerprint] is this device's
  /// published fingerprint (nullable: unavailable ⇒ membership detection is
  /// skipped); [isCancelled] is polled between fetches.
  RefreshRun({
    required NetworkRepository repository,
    required DescriptorFetcher fetchDescriptor,
    required int Function() clock,
    required int concurrency,
    required String? ownFingerprint,
    required bool Function() isCancelled,
  }) : _repository = repository,
       _fetchDescriptor = fetchDescriptor,
       _clock = clock,
       _concurrency = concurrency,
       _ownFingerprint = ownFingerprint,
       _isCancelled = isCancelled;

  final NetworkRepository _repository;
  final DescriptorFetcher _fetchDescriptor;
  final int Function() _clock;
  final int _concurrency;
  final String? _ownFingerprint;
  final bool Function() _isCancelled;

  late final NetworkDiscoveryPlan _plan;

  /// siteUrl → this run's computed state (lazily seeded from the saved row or
  /// the discovery hints). At the end, seeds that CHANGED are updated and
  /// discovered rows are inserted — one `applyRefresh` transaction (§5.6/5).
  final Map<String, NetworkLibrary> _states = {};

  /// siteUrl → the row as STORED when the run started. The move detector
  /// needs the canonical row's stored fingerprint (a fact), which the mutable
  /// states may already have changed.
  final Map<String, NetworkLibrary> _savedRows = {};

  /// Move offers produced by this run (ephemeral; see the class doc).
  final List<LibraryMoveCandidate> _moveCandidates = [];

  /// siteUrl → the row's state BEFORE this run touched it (the saved row for
  /// seeds, the hint-built fresh row for discoveries). A conflict resets a
  /// row to this baseline (D12: "updates nothing else"), and the report's
  /// `conflicts`/`pendingMemberships` counts are derived by comparing the
  /// final states against it — so a later revocation can never leave a
  /// counter off by one.
  final Map<String, NetworkLibrary> _baselines = {};

  /// fingerprint → siteUrl of the row that OWNS it. Pre-loaded from the
  /// STORED rows (facts from earlier fetches and card scans) and extended
  /// only by a row's OWN successful fetch. Hub hints are never entered here:
  /// a claim about someone else is not ownership.
  final Map<String, String> _fpOwners = {};

  /// Fingerprints adopted for the first time in THIS run (the owning row had
  /// none stored). If a second row publishes one of these, the claim is
  /// ambiguous — nobody had it before — so both rows are flagged.
  final Set<String> _adoptedThisRun = {};

  /// Fingerprints two no-prior-claim rows fought over this run: nobody may
  /// adopt them until the user resolves the badges (deterministic, D12).
  final Set<String> _contested = {};

  int _fetched = 0;
  int _unreachable = 0;
  int _invalid = 0;
  int _schemaTooNew = 0;
  final List<String> _noLongerListed = [];

  /// Runs the refresh and returns its report (or a typed storage failure from
  /// the ONE write transaction).
  Future<Either<Failure, RefreshReport>> execute() async {
    final rows = await _repository.loadAll();
    _plan = NetworkDiscoveryPlan(seeds: rows);
    for (final row in rows) {
      _savedRows[row.siteUrl] = row;
      final fp = row.fingerprint;
      if (fp != null) _fpOwners.putIfAbsent(fp, () => row.siteUrl);
    }

    // Fetch rounds: seeds first, then each discovery generation, until the
    // plan has nothing pending. The depth cap inside the plan bounds this
    // loop (≤ 3 rounds: seeds, depth-1, depth-2).
    while (true) {
      final batch = _plan.pending();
      if (batch.isEmpty) break;
      await _fetchRound(batch);
      // Cancel BETWEEN fetches (§5.6): stop starting new ones, then fall
      // through — the partial results below are still applied.
      if (_isCancelled()) break;
    }

    // Discovered rows append after the user's own order (sortOrder keeps the
    // migrated bookmark order first — repository loadAll sorts by it).
    var nextSort = 0;
    for (final row in rows) {
      if (row.sortOrder > nextSort) nextSort = row.sortOrder;
    }
    for (final planned in _plan.discovered) {
      nextSort++;
      _states[planned.siteUrl] = _stateFor(
        planned,
      ).copyWith(sortOrder: nextSort);
    }

    // Belt and braces: whatever the descriptors claimed, the set we hand to
    // the ONE transaction must not contain two rows with one fingerprint, or
    // the UNIQUE constraint would roll the whole run back (H1).
    _ensureUniqueFingerprints(rows);

    final updated = <NetworkLibrary>[
      for (final saved in rows)
        if (_states[saved.siteUrl] case final state? when !state.sameAs(saved))
          state,
    ];
    final inserted = <NetworkLibrary>[
      for (final planned in _plan.discovered) _states[planned.siteUrl]!,
    ];

    // The baselines guard (review M1): the run READ `rows` minutes ago. Any
    // row the user edited meanwhile (membership decision, card scan) no
    // longer matches its baseline inside the repository's transaction, so
    // that row's write is skipped — the user's edit always wins.
    final applied = await _repository.applyRefresh(
      updated,
      inserted,
      baselines: rows,
    );
    return applied.map(
      (result) => RefreshReport(
        fetched: _fetched,
        unreachable: _unreachable,
        invalid: _invalid,
        schemaTooNew: _schemaTooNew,
        discovered: result.inserted,
        keptLocalChanges: result.keptLocal,
        truncated: _plan.truncated,
        pendingMemberships: _countNewlyPending(),
        conflicts: _countNewConflicts(),
        cancelled: _isCancelled(),
        noLongerListed: List.unmodifiable(_noLongerListed),
        moveCandidates: List.unmodifiable(_moveCandidates),
      ),
    );
  }

  /// Fetches one round (all currently-pending rows) with [_concurrency]
  /// workers pulling from a shared queue. Single-isolate Dart: the
  /// check-and-take below has no await in between, so no worker can take the
  /// same row twice.
  Future<void> _fetchRound(List<PlannedRow> batch) async {
    final queue = [...batch];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (_isCancelled()) return; // never START a fetch after cancel
        final planned = queue.removeAt(0);
        final result = await _fetchDescriptor(planned.descriptorUrl);
        _handle(planned, result);
      }
    }

    final workers = queue.length < _concurrency ? queue.length : _concurrency;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }

  void _handle(PlannedRow planned, DescriptorFetchResult result) {
    final row = _stateFor(planned);
    switch (result) {
      case DescriptorFetched(:final descriptor):
        // The plan learns first so a discovery made by THIS descriptor is
        // queued even if applying the row below flags a conflict.
        _plan.recordFetched(planned, descriptor);
        _fetched++;
        _applyDescriptor(planned, row, descriptor);
      case DescriptorRefused(:final reason):
        _plan.recordRefused(planned);
        _applyRefusal(row, reason);
    }
  }

  /// §5.6 step 2 — what a valid descriptor changes on its row.
  void _applyDescriptor(
    PlannedRow planned,
    NetworkLibrary row,
    LibraryDescriptor descriptor,
  ) {
    final storedFp = row.fingerprint;
    final fetchedFp = descriptor.fingerprint;

    // (a) The row already knows a fingerprint and the site now publishes a
    // DIFFERENT one: flag, update nothing else (D12 — never auto-merge).
    if (storedFp != null && storedFp != fetchedFp) {
      _flagConflict(row.siteUrl);
      return;
    }
    // (b) A discovered row: the hub that listed it claimed a fingerprint.
    // The claim is checked against the member's OWN site; a contradiction is
    // a conflict (someone is wrong — the user decides), and the claim is
    // never stored as the member's identity either way.
    final hint = planned.hintFingerprint;
    if (hint != null && hint != fetchedFp) {
      _flagConflict(row.siteUrl);
      return;
    }
    // (c) The fetched fingerprint is contested or already owned by ANOTHER
    // row: fail closed on this row (D12 cross-row collision). If the owner
    // only adopted it in THIS run, nobody held it before — flag the owner
    // too, so the result is the same whichever response arrived first.
    if (_contested.contains(fetchedFp)) {
      _flagConflict(row.siteUrl);
      return;
    }
    final owner = _fpOwners[fetchedFp];
    if (owner != null && owner != row.siteUrl) {
      if (_adoptedThisRun.contains(fetchedFp)) {
        _contested.add(fetchedFp);
        _fpOwners.remove(fetchedFp);
        _flagConflict(owner);
        _flagConflict(row.siteUrl);
        return;
      }
      // C10/R17: a move is possible — check BEFORE the conflict flag below,
      // so the user can be offered a neutral choice instead of a dead end.
      if (_recordMoveCandidate(row, descriptor, owner)) return;
      _flagConflict(row.siteUrl);
      return;
    }
    _fpOwners[fetchedFp] = row.siteUrl;
    if (storedFp == null) _adoptedThisRun.add(fetchedFp);

    // §5.6 step 4 — own membership, both directions.
    var membership = row.membership;
    final listsMe =
        _ownFingerprint != null &&
        descriptor.members.any((m) => m.fingerprint == _ownFingerprint);
    if (listsMe) {
      // pending prompts the user; declined is NEVER re-prompted (only the
      // user's own "Reconsider" resets it); confirmed stays confirmed.
      if (membership == MembershipState.none) {
        membership = MembershipState.pending;
      }
    } else if (_ownFingerprint != null &&
        membership == MembershipState.confirmed) {
      _noLongerListed.add(row.siteUrl); // user decides; state unchanged
    }

    // "Confirmed by member" (design 2026-10-18): this row was surfaced by a
    // hub's `members` list (the hub's CLAIM); the member's OWN descriptor
    // naming that hub in `memberOf` is the member's CONSENT. Both URLs are
    // BookmarkUrl-normalized (codec §3.1, rows D13), so a plain string
    // compare is exact. A member that removed the link flips back to false.
    final listedBy = row.listedByHubUrl;
    final confirmedByMember =
        listedBy != null && descriptor.memberOf.contains(listedBy);

    _states[row.siteUrl] = row.copyWith(
      name: descriptor.name,
      fingerprint: fetchedFp,
      location: descriptor.location,
      precision: descriptor.precision,
      confirmedByMember: confirmedByMember,
      // A library that turned sharing OFF publishes no location block: the
      // stored pin must be CLEARED, and only the wholesale applyRefresh path
      // can persist a null (copyWith's clear flag — handoff §3).
      clearLocation: descriptor.location == null,
      membership: membership,
      fetchStatus: FetchStatus.ok,
      fetchedAt: _clock(),
      // "memberVerified = isMember && match" (§5.6 step 2): the card-scan
      // fingerprint (the row's stored one) agrees with the published one.
      memberVerified: row.isMember && storedFp != null && storedFp == fetchedFp,
    );
  }

  /// Records an ephemeral move offer when the evidence is complete, and
  /// returns true (the row is then left exactly as stored: no fingerprint
  /// adoption, no conflict badge, no write).
  ///
  /// The plan's C10/R17 conditions, each one deliberate:
  ///  - the address that already owns the fingerprint is a SAVED row and still
  ///    stores it as a fact (not one adopted moments ago in this run);
  ///  - the fetched descriptor publishes the same fingerprint AND declares its
  ///    own `siteUrl` to be the address it was fetched from (a payload from a
  ///    different directory/origin is never evidence);
  ///  - the other address came from an explicit user action — a bookmark/URL
  ///    add (`source == bookmark`, which includes migrated bookmarks) or an
  ///    in-person card scan (`source == card`). A DISCOVERED row is somebody
  ///    else's claim, so it keeps the existing conflict behavior;
  ///  - the other row carries no identity of its own yet (once it does, this
  ///    is an identity conflict, the stricter path).
  bool _recordMoveCandidate(
    NetworkLibrary row,
    LibraryDescriptor descriptor,
    String ownerSiteUrl,
  ) {
    final saved = _savedRows[ownerSiteUrl];
    if (saved == null || row.id == 0 || saved.id == 0) return false;
    if (saved.fingerprint != descriptor.fingerprint) return false;
    if (row.fingerprint != null) return false;
    if (row.source == NetworkSource.discovered) return false;
    if (descriptor.siteUrl != row.siteUrl) return false;
    if (ownerSiteUrl == row.siteUrl) return false;

    final candidate = LibraryMoveCandidate(
      savedRowId: saved.id,
      savedSiteUrl: saved.siteUrl,
      savedName: saved.name,
      fetchedSiteUrl: row.siteUrl,
      fetchedName: descriptor.name,
      fingerprint: descriptor.fingerprint,
      fetchedLocation: descriptor.location,
      fetchedPrecision: descriptor.precision,
      fetchedAt: _clock(),
      fetchedSource: row.source,
    );
    for (final existing in _moveCandidates) {
      if (existing.sameAs(candidate)) return true; // already offered
    }
    _moveCandidates.add(candidate);
    return true;
  }

  /// §5.6 step 2 — refusal mapping. Cached name/location/fetchedAt stay: a
  /// failed fetch means "no news", not "delete what I know" (offline shows
  /// the cached list).
  void _applyRefusal(NetworkLibrary row, DescriptorRefusal reason) {
    final status = switch (reason) {
      DescriptorRefusal.invalid => FetchStatus.invalid,
      DescriptorRefusal.schemaTooNew => FetchStatus.schemaTooNew,
      // disallowedUrl | redirectRefused | tooManyRedirects | httpStatus |
      // tooLarge | timedOut | transport — all "could not reach a valid file".
      _ => FetchStatus.unreachable,
    };
    switch (status) {
      case FetchStatus.unreachable:
        _unreachable++;
      case FetchStatus.invalid:
        _invalid++;
      case FetchStatus.schemaTooNew:
        _schemaTooNew++;
      case FetchStatus.never:
      case FetchStatus.ok:
      case FetchStatus.identityConflict:
        break; // unreachable: the mapping above yields only the three above
    }
    // A KNOWN identity conflict outranks a failed fetch: the badge must not
    // flicker away just because the site went offline (fail closed, visible).
    //
    // The one exception is a POSITIVE answer that this address no longer
    // publishes a library at all (404/410), which is exactly what a Pitak
    // moved page serves once a move has completed. The dispute was about what
    // this address published; it now publishes nothing, so the stale badge
    // gives way to `unreachable`. Another address that still claims the
    // identity keeps its own badge or move offer, so a live dispute stays
    // visible (decided 2026-10-31, handoff §12). An offline site (timeout,
    // transport, 5xx) still keeps the badge.
    if (row.fetchStatus == FetchStatus.identityConflict &&
        reason != DescriptorRefusal.notPublished) {
      return;
    }
    _states[row.siteUrl] = row.copyWith(fetchStatus: status);
  }

  /// Flags [siteUrl] as an identity conflict: the row goes back to its
  /// baseline (whatever this run may already have applied to it is undone —
  /// D12 "updates nothing else") with the conflict badge on and
  /// `memberVerified` off (a disputed identity is, by definition, not a
  /// verified one).
  void _flagConflict(String siteUrl) {
    final baseline = _baselines[siteUrl];
    if (baseline == null) return; // not a row of this run — nothing to flag
    _states[siteUrl] = baseline.copyWith(
      fetchStatus: FetchStatus.identityConflict,
      memberVerified: false,
    );
  }

  /// Last line of defence before the ONE transaction: no two rows handed to
  /// `applyRefresh` (or left untouched in the table) may share a fingerprint.
  /// The per-descriptor rules above already guarantee this; should a future
  /// change break that invariant, this pass trades the duplicates' identity
  /// for a visible conflict badge instead of losing the whole run.
  void _ensureUniqueFingerprints(List<NetworkLibrary> stored) {
    final seen = <String, String>{}; // fingerprint → siteUrl
    // Stored fingerprints are facts and win ties; visit saved rows first.
    final ordered = [
      for (final saved in stored) _states[saved.siteUrl] ?? saved,
      for (final planned in _plan.discovered) _states[planned.siteUrl]!,
    ];
    for (final row in ordered) {
      final fp = row.fingerprint;
      if (fp == null) continue;
      final first = seen[fp];
      if (first == null) {
        seen[fp] = row.siteUrl;
        continue;
      }
      if (first == row.siteUrl) continue;
      final baseline = _baselines[row.siteUrl];
      if (baseline == null) {
        // An untouched saved row that duplicates an earlier one: the table
        // already holds both, so this run cannot have caused it — leave it.
        continue;
      }
      _states[row.siteUrl] = baseline.copyWith(
        fetchStatus: FetchStatus.identityConflict,
        memberVerified: false,
        // Only a fingerprint this run tried to ADOPT is dropped; a stored
        // one stays (it is the table's fact, and the table accepted it).
        clearFingerprint: baseline.fingerprint == null,
      );
    }
  }

  /// Rows that moved to `pending` in this run (baseline was `none`).
  int _countNewlyPending() {
    var count = 0;
    for (final entry in _states.entries) {
      final baseline = _baselines[entry.key];
      if (baseline != null &&
          baseline.membership == MembershipState.none &&
          entry.value.membership == MembershipState.pending) {
        count++;
      }
    }
    return count;
  }

  /// Rows that carry the conflict badge now but did not at baseline.
  int _countNewConflicts() {
    var count = 0;
    for (final entry in _states.entries) {
      final baseline = _baselines[entry.key];
      if (baseline != null &&
          baseline.fetchStatus != FetchStatus.identityConflict &&
          entry.value.fetchStatus == FetchStatus.identityConflict) {
        count++;
      }
    }
    return count;
  }

  NetworkLibrary _stateFor(PlannedRow planned) =>
      _states.putIfAbsent(planned.siteUrl, () {
        final initial = _initialState(planned);
        _baselines[planned.siteUrl] = initial;
        return initial;
      });

  /// The starting state of a planned row: the stored row for seeds; for a
  /// discovery, a fresh `discovered` row built from the hub's member-entry
  /// NAME hint (re-validated — the codec checked it, but a hostile in-process
  /// caller of the plan must not be able to smuggle a name past §6). The
  /// hub's FINGERPRINT hint is deliberately NOT copied in: it stays in the
  /// plan and is only compared against the member's own fetch (H1).
  NetworkLibrary _initialState(PlannedRow planned) {
    final saved = planned.saved;
    if (saved != null) return saved;
    return NetworkLibrary(
      siteUrl: planned.siteUrl,
      name: NetworkName.normalizeOrNull(planned.hintName) ?? '',
      source: NetworkSource.discovered,
      listedByHubUrl: planned.listedByHubUrl,
      createdAt: _clock(),
    );
  }
}
