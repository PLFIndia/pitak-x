/// The bounded discovery planner (network domain, pure Dart; libNetwork.md
/// §5.6 step 1+3, D10).
///
/// Refresh needs to answer ONE policy question without touching the network:
/// "given the rows I have and the descriptors that arrived, which URLs do I
/// look at next?" Keeping that question in a pure object makes the whole
/// discovery policy unit-testable (no HTTP, no Drift) and keeps the
/// `RefreshNetworkUseCase` focused on applying results.
///
/// The policy (D10 — "bounded, two expansions max"):
///  - **Seeds** are every saved row; all of them get fetched.
///  - `memberOf` links are followed from seeds and from hubs discovered via
///    `memberOf` — a discovered hub is fetched AND its lists are expanded.
///  - `members` lists are expanded only for seeds and those hubs: each member
///    becomes a **leaf** row (fetched for its pin only; a leaf's own
///    `members`/`memberOf` are never expanded — §5.6).
///  - Nothing expands beyond depth [NetworkDiscoveryPlan.maxExpansionDepth]
///    (2 hops from a seed), so a hostile hub-of-hubs chain can never crawl
///    the world.
///  - Hard cap: [NetworkDiscoveryPlan.maxRowsPerRun] rows per run (seeds +
///    discovered); when the cap refuses a new row,
///    [NetworkDiscoveryPlan.truncated] is reported (§6).
///  - Duplicate URLs collapse: a URL already planned (as any role) is never
///    planned twice — the first role wins.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// Why a row is in the plan — decides whether its descriptor may expand.
enum DiscoveryRole {
  /// A row the user saved (bookmark, card, or an earlier discovery). Always
  /// fetched; always allowed to expand (within the depth cap).
  seed,

  /// Discovered through another descriptor's `memberOf` list: a hub. Fetched
  /// and allowed to expand (within the depth cap).
  hub,

  /// Discovered through a `members` list. Fetched for its pin only — never
  /// expands (§5.6: "their `members`/`memberOf` are not expanded").
  leaf,
}

/// One row the plan wants fetched, with everything the use case needs to
/// build its `NetworkLibrary` state when the row is new.
final class PlannedRow {
  const PlannedRow._({
    required this.siteUrl,
    required this.role,
    required this.depth,
    this.saved,
    this.listedByHubUrl,
    this.hintName,
    this.hintFingerprint,
  });

  /// The row's published site root URL (the natural key, D13).
  final String siteUrl;

  /// Why this row is in the plan.
  final DiscoveryRole role;

  /// Expansion hops from the nearest seed: seeds are 0, rows discovered from
  /// a seed's descriptor are 1, and so on. Nothing expands at
  /// `depth >= NetworkDiscoveryPlan.maxExpansionDepth`.
  final int depth;

  /// The stored row for seeds; null for rows discovered in this run.
  final NetworkLibrary? saved;

  /// For leaves: the hub whose `members` list surfaced this row (§5.6).
  final String? listedByHubUrl;

  /// Display name carried by the discovering `members` entry, if any.
  final String? hintName;

  /// Fingerprint carried by the discovering `members` entry, if any. A leaf's
  /// own fetch must MATCH it, or the row is flagged `identityConflict` (D12).
  final String? hintFingerprint;

  /// The URL of this row's published descriptor (`<siteUrl>library.json`).
  String get descriptorUrl =>
      Uri.parse(siteUrl).resolve('library.json').toString();
}

/// Plans one refresh run's fetches. Feed every fetch outcome back through
/// [recordFetched]/[recordRefused]; [pending] then yields the next URLs.
final class NetworkDiscoveryPlan {
  /// Plans a run over [seeds] (all saved rows). [maxRows] exists for tests;
  /// production always uses [maxRowsPerRun].
  NetworkDiscoveryPlan({
    required List<NetworkLibrary> seeds,
    this.maxRows = maxRowsPerRun,
  }) {
    for (final seed in seeds) {
      // putIfAbsent: the table's unique key makes duplicate siteUrls
      // impossible, but the plan must stay sane even if one ever slipped in.
      _known.putIfAbsent(
        seed.siteUrl,
        () => PlannedRow._(
          siteUrl: seed.siteUrl,
          role: DiscoveryRole.seed,
          depth: 0,
          saved: seed,
        ),
      );
    }
  }

  /// Hard cap on rows per refresh run (§6): seeds + discovered. Predictable
  /// traffic no matter what any descriptor claims (D10).
  static const int maxRowsPerRun = 500;

  /// Maximum expansion depth ("two expansions max", D10): a seed (depth 0)
  /// may discover rows at depth 1, those may discover rows at depth 2, and
  /// depth-2 rows are terminal — fetched and applied, never expanded.
  static const int maxExpansionDepth = 2;

  /// Rows per run this plan honours (defaults to [maxRowsPerRun]).
  final int maxRows;

  // Insertion-ordered so pending() and discovered are deterministic.
  final Map<String, PlannedRow> _known = {};
  final Set<String> _settled = {};
  bool _truncated = false;

  /// True when the row cap refused at least one discovery this run — the UI
  /// says so plainly (§5.6 step 3: "truncation is reported").
  bool get truncated => _truncated;

  /// Every planned row, in discovery order (seeds first).
  List<PlannedRow> get all => _known.values.toList();

  /// Planned rows whose fetch outcome has not been recorded yet.
  List<PlannedRow> pending() => [
    for (final row in _known.values)
      if (!_settled.contains(row.siteUrl)) row,
  ];

  /// Rows discovered during this run (everything except the seeds), in
  /// discovery order — the rows `applyRefresh` will INSERT.
  List<PlannedRow> get discovered => [
    for (final row in _known.values)
      if (row.role != DiscoveryRole.seed) row,
  ];

  /// The planned row for [siteUrl], when the plan knows it.
  PlannedRow? rowFor(String siteUrl) => _known[siteUrl];

  /// Records a successful fetch and queues the discoveries its descriptor
  /// earns (role + depth rules in the library doc above).
  void recordFetched(PlannedRow row, LibraryDescriptor descriptor) {
    _settled.add(row.siteUrl);
    if (!_canExpand(row)) return;
    // memberOf ⇒ hubs (expanded further, within the depth cap).
    for (final hubUrl in descriptor.memberOf) {
      _discover(hubUrl, role: DiscoveryRole.hub, depth: row.depth + 1);
    }
    // members ⇒ leaves, carrying the hub's own URL + the entry's hints.
    for (final member in descriptor.members) {
      _discover(
        member.siteUrl,
        role: DiscoveryRole.leaf,
        depth: row.depth + 1,
        listedByHubUrl: row.siteUrl,
        hintName: member.name,
        hintFingerprint: member.fingerprint,
      );
    }
  }

  /// Records a refused fetch: the row is settled and expands nothing.
  void recordRefused(PlannedRow row) {
    _settled.add(row.siteUrl);
  }

  bool _canExpand(PlannedRow row) =>
      row.role != DiscoveryRole.leaf && row.depth < maxExpansionDepth;

  void _discover(
    String siteUrl, {
    required DiscoveryRole role,
    required int depth,
    String? listedByHubUrl,
    String? hintName,
    String? hintFingerprint,
  }) {
    if (_known.containsKey(siteUrl)) return; // duplicates collapse
    if (_known.length >= maxRows) {
      _truncated = true; // cap hit: stop discovering, report (§6)
      return;
    }
    _known[siteUrl] = PlannedRow._(
      siteUrl: siteUrl,
      role: role,
      depth: depth,
      listedByHubUrl: listedByHubUrl,
      hintName: hintName,
      hintFingerprint: hintFingerprint,
    );
  }
}
