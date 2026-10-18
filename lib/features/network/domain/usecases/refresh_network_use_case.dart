/// The Refresh algorithm (network domain use case; libNetwork.md §5.6, D10,
/// D11, D12).
///
/// One user tap reads every saved library's published `library.json`, applies
/// what it learns (name, pin, fingerprint, membership signals), discovers the
/// bounded two-hop neighbourhood (`NetworkDiscoveryPlan`), and writes the
/// whole run as ONE repository transaction. Rules that matter:
///
///  - **User-initiated only** (D11): nothing here ever runs by itself.
///  - **Bounded** (§6): concurrency 4, per-fetch deadline/cap live inside the
///    injected [DescriptorFetcher] (the bounded fetcher), discovery is capped
///    by the plan.
///  - **Cancellable**: [RefreshNetworkUseCase.call] checks `isCancelled`
///    BETWEEN fetches; a cancelled run still applies its partial results
///    (each fetched row is individually valid) and reports `cancelled: true`.
///  - **Fail closed on identity** (D12): a fetched fingerprint that
///    contradicts the row's stored one, or that already belongs to a
///    DIFFERENT row, flags `identityConflict` and updates NOTHING else — no
///    silent merges, ever.
///  - **A fingerprint is a FACT only from a row's own fetch or card scan.**
///    A hub's `members` entry is a CLAIM about someone else: discovered rows
///    therefore start with `fingerprint == null`, and the hub's hint is only
///    COMPARED against what the member's own site publishes (a mismatch is a
///    conflict). Storing the claim as if it were the member's identity let
///    one hostile — or merely stale — hub file collide with the table's
///    UNIQUE(fingerprint) and make every refresh fail (review finding H1).
///  - **Deterministic under concurrency**: when two sites that had NO stored
///    fingerprint both publish the same one in one run, BOTH are flagged and
///    neither adopts it — the outcome never depends on which response landed
///    first. A final uniqueness pass guarantees the single transaction can
///    never trip the UNIQUE constraint, whatever the descriptors claimed.
///  - **Refusals never erase cached data**: an unreachable/invalid/schemaTooNew
///    fetch only sets `fetchStatus`, so the offline list keeps its pins and
///    names (S4 acceptance).
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_discovery_plan.dart';
import 'package:pitaka/features/network/domain/refresh_report.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

// Re-exported: callers that run the use case also read its report.
export 'package:pitaka/features/network/domain/refresh_report.dart';

/// Runs one refresh over the saved rows (§5.6).
final class RefreshNetworkUseCase {
  /// Creates the use case over its ports. [clock] and [concurrency] are
  /// injectable for tests; production uses the DI clock and 4 workers.
  RefreshNetworkUseCase({
    required NetworkRepository repository,
    required DescriptorFetcher fetchDescriptor,
    int Function()? clock,
    int concurrency = defaultConcurrency,
  }) : _repository = repository,
       _fetchDescriptor = fetchDescriptor,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _concurrency = concurrency < 1 ? 1 : concurrency;

  /// In-flight descriptor fetches (§6 "Concurrency"). Four balances a busy
  /// hub list against mobile radios and the OSM-style "be polite" norm.
  static const int defaultConcurrency = 4;

  final NetworkRepository _repository;
  final DescriptorFetcher _fetchDescriptor;
  final int Function() _clock;
  final int _concurrency;

  /// Refreshes the network. [ownFingerprint] (this device's published
  /// fingerprint, or null when the identity is unavailable) enables the
  /// membership detection of §5.6 step 4; [isCancelled] is polled between
  /// fetches. Left is only ever a storage failure — every network outcome is
  /// data in the [RefreshReport], never an error (D11: refresh is best-effort
  /// by design).
  Future<Either<Failure, RefreshReport>> call({
    String? ownFingerprint,
    bool Function()? isCancelled,
  }) {
    // All run state lives in one _Run object: the use case itself is shared
    // (DI hands out ONE instance) and must stay safe across concurrent calls.
    return _Run(
      repository: _repository,
      fetchDescriptor: _fetchDescriptor,
      clock: _clock,
      concurrency: _concurrency,
      ownFingerprint:
          (ownFingerprint != null && LibraryFingerprint.isValid(ownFingerprint))
          ? ownFingerprint
          : null,
      isCancelled: isCancelled ?? () => false,
    ).execute();
  }
}

/// The mutable state of ONE refresh run (see [RefreshNetworkUseCase.call]).
final class _Run {
  _Run({
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

  Future<Either<Failure, RefreshReport>> execute() async {
    final rows = await _repository.loadAll();
    _plan = NetworkDiscoveryPlan(seeds: rows);
    for (final row in rows) {
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

    final applied = await _repository.applyRefresh(updated, inserted);
    return applied.map(
      (_) => RefreshReport(
        fetched: _fetched,
        unreachable: _unreachable,
        invalid: _invalid,
        schemaTooNew: _schemaTooNew,
        discovered: inserted.length,
        truncated: _plan.truncated,
        pendingMemberships: _countNewlyPending(),
        conflicts: _countNewConflicts(),
        cancelled: _isCancelled(),
        noLongerListed: List.unmodifiable(_noLongerListed),
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
      }
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

    _states[row.siteUrl] = row.copyWith(
      name: descriptor.name,
      fingerprint: fetchedFp,
      location: descriptor.location,
      precision: descriptor.precision,
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
    if (row.fetchStatus == FetchStatus.identityConflict) return;
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
