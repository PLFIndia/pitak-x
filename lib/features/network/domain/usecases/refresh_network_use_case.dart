/// The Refresh algorithm (network domain use case; docs/ARCHITECTURE.md §5.6 discovery bounds,
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
///  - **A move offer is evidence, not a decision** (Cloudflare plan C10/R17):
///    when a row the USER added at another address publishes the same
///    fingerprint a saved row already holds as a FACT, this run records an
///    ephemeral library-move offer instead of flagging a conflict. The
///    row keeps its null fingerprint (no duplicate identity is persisted) and
///    nothing is written or re-pointed until the user chooses an address.
///  - **Reciprocal consent is recorded** (design 2026-10-18): for a row a hub
///    LISTED (`listedByHubUrl`), the member's own `memberOf` linking back to
///    that hub sets `confirmedByMember` — the hub's claim plus the member's
///    agreement, kept as two separate facts so viewers can tell them apart.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/refresh_report.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_run.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';

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
    return RefreshRun(
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
