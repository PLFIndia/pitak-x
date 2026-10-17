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
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

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

  /// fingerprint → siteUrl of the row that "owns" it. Preloaded from the
  /// stored rows and extended by member-entry hints and fetched descriptors;
  /// the cross-row collision check of D12 reads it.
  final Map<String, String> _fpOwners = {};

  /// Discovered rows whose member-entry hint fingerprint is registered.
  final Set<String> _hintsRegistered = {};

  int _fetched = 0;
  int _unreachable = 0;
  int _invalid = 0;
  int _schemaTooNew = 0;
  int _pendingMemberships = 0;
  int _conflicts = 0;
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

    final updated = <NetworkLibrary>[
      for (final saved in rows)
        if (_states[saved.siteUrl] case final state? when !state.sameAs(saved))
          state,
    ];
    // Discovered rows append after the user's own order (sortOrder keeps the
    // migrated bookmark order first — repository loadAll sorts by it).
    var nextSort = 0;
    for (final row in rows) {
      if (row.sortOrder > nextSort) nextSort = row.sortOrder;
    }
    final inserted = <NetworkLibrary>[];
    for (final planned in _plan.discovered) {
      nextSort++;
      inserted.add(_stateFor(planned).copyWith(sortOrder: nextSort));
    }

    final applied = await _repository.applyRefresh(updated, inserted);
    return applied.map(
      (_) => RefreshReport(
        fetched: _fetched,
        unreachable: _unreachable,
        invalid: _invalid,
        schemaTooNew: _schemaTooNew,
        discovered: inserted.length,
        truncated: _plan.truncated,
        pendingMemberships: _pendingMemberships,
        conflicts: _conflicts,
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
        _registerDiscoveredHints();
        _fetched++;
        _applyDescriptor(row, descriptor);
      case DescriptorRefused(:final reason):
        _plan.recordRefused(planned);
        _applyRefusal(row, reason);
    }
  }

  /// §5.6 step 2 — what a valid descriptor changes on its row.
  void _applyDescriptor(NetworkLibrary row, LibraryDescriptor descriptor) {
    final storedFp = row.fingerprint;
    // (a) The row already knows a fingerprint and the site now publishes a
    // DIFFERENT one: flag, update nothing else (D12 — never auto-merge).
    if (storedFp != null && storedFp != descriptor.fingerprint) {
      _flagConflict(row);
      return;
    }
    // (b) The fetched fingerprint already belongs to ANOTHER row: same
    // fail-closed treatment on this row (D12 cross-row collision).
    final owner = _fpOwners[descriptor.fingerprint];
    if (owner != null && owner != row.siteUrl) {
      _flagConflict(row);
      return;
    }
    _fpOwners[descriptor.fingerprint] = row.siteUrl;

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
        _pendingMemberships++;
      }
    } else if (_ownFingerprint != null &&
        membership == MembershipState.confirmed) {
      _noLongerListed.add(row.siteUrl); // user decides; state unchanged
    }

    _states[row.siteUrl] = row.copyWith(
      name: descriptor.name,
      fingerprint: descriptor.fingerprint,
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
      memberVerified:
          row.isMember &&
          storedFp != null &&
          storedFp == descriptor.fingerprint,
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

  void _flagConflict(NetworkLibrary row) {
    _states[row.siteUrl] = row.copyWith(
      fetchStatus: FetchStatus.identityConflict,
    );
    _conflicts++;
  }

  /// Member entries carry a fingerprint hint; registering it immediately
  /// means a LATER fetch of some other URL publishing the same fingerprint
  /// is flagged as the collision (D12 works across discoveries too).
  void _registerDiscoveredHints() {
    for (final planned in _plan.discovered) {
      if (!_hintsRegistered.add(planned.siteUrl)) continue;
      final hint = planned.hintFingerprint;
      if (hint != null) _fpOwners.putIfAbsent(hint, () => planned.siteUrl);
    }
  }

  NetworkLibrary _stateFor(PlannedRow planned) =>
      _states.putIfAbsent(planned.siteUrl, () => _initialState(planned));

  /// The starting state of a planned row: the stored row for seeds; for a
  /// discovery, a fresh `discovered` row built from the hub's member-entry
  /// hints (name re-validated — the codec checked it, but a hostile in-process
  /// caller of the plan must not be able to smuggle a name past §6).
  NetworkLibrary _initialState(PlannedRow planned) {
    final saved = planned.saved;
    if (saved != null) return saved;
    return NetworkLibrary(
      siteUrl: planned.siteUrl,
      name: NetworkName.normalizeOrNull(planned.hintName) ?? '',
      fingerprint: planned.hintFingerprint,
      source: NetworkSource.discovered,
      listedByHubUrl: planned.listedByHubUrl,
      createdAt: _clock(),
    );
  }
}
