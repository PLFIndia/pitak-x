import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_discovery_plan.dart';

/// Policy tests for [NetworkDiscoveryPlan] (libNetwork.md §7 S4, D10). The
/// planner is pure — no IO anywhere in this file.
void main() {
  const hubUrl = 'https://hub.github.io/pitak/';
  const hub2Url = 'https://hub2.github.io/pitak/';
  const seedUrl = 'https://seed.github.io/pitak/';
  const m1Url = 'https://m1.github.io/pitak/';
  const m2Url = 'https://m2.github.io/pitak/';
  const m3Url = 'https://m3.github.io/pitak/';

  NetworkLibrary row(String siteUrl, {int id = 1, int sortOrder = 0}) =>
      NetworkLibrary(id: id, siteUrl: siteUrl, sortOrder: sortOrder);

  LibraryDescriptor descriptor(
    String siteUrl, {
    List<MemberEntry> members = const [],
    List<String> memberOf = const [],
  }) => LibraryDescriptor(
    // The planner never validates fingerprints (the codec already did);
    // a placeholder keeps the tests readable.
    fingerprint: '0' * 64,
    name: 'Descriptor of $siteUrl',
    siteUrl: siteUrl,
    updatedAt: 1,
    members: members,
    memberOf: memberOf,
  );

  MemberEntry member(String siteUrl, {String? name, String? fingerprint}) =>
      MemberEntry(
        fingerprint: fingerprint ?? '0' * 64,
        siteUrl: siteUrl,
        name: name,
      );

  group('seeds', () {
    test('every saved row is pending exactly once, in order', () {
      final plan = NetworkDiscoveryPlan(
        seeds: [row(seedUrl), row(hubUrl, id: 2, sortOrder: 1)],
      );
      expect(plan.pending().map((p) => p.siteUrl), [seedUrl, hubUrl]);
      expect(plan.pending().every((p) => p.role == DiscoveryRole.seed), isTrue);
      expect(plan.pending().every((p) => p.depth == 0), isTrue);
      expect(plan.pending().every((p) => p.saved != null), isTrue);

      plan.recordRefused(plan.rowFor(seedUrl)!);
      expect(plan.pending().map((p) => p.siteUrl), [hubUrl]);
      // Settled rows never come back.
      plan.recordRefused(plan.rowFor(hubUrl)!);
      expect(plan.pending(), isEmpty);
      expect(plan.discovered, isEmpty);
      expect(plan.truncated, isFalse);
    });

    test('a refused row expands nothing', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      plan.recordRefused(plan.rowFor(seedUrl)!);
      expect(plan.pending(), isEmpty);
      expect(plan.discovered, isEmpty);
    });
  });

  group('expansion depth (D10: two expansions max)', () {
    test('a hub seed expands its members list — 1 expansion', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(hubUrl)]);
      plan.recordFetched(
        plan.rowFor(hubUrl)!,
        descriptor(hubUrl, members: [member(m1Url, name: 'M One')]),
      );

      final pending = plan.pending();
      expect(pending, hasLength(1));
      expect(pending.single.siteUrl, m1Url);
      expect(pending.single.role, DiscoveryRole.leaf);
      expect(pending.single.depth, 1);
      expect(pending.single.listedByHubUrl, hubUrl);
      expect(pending.single.hintName, 'M One');
      expect(pending.single.saved, isNull);
    });

    test('member seed → memberOf hub → hub members — 2 expansions', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      // Expansion 1: the seed's memberOf surfaces the hub.
      plan.recordFetched(
        plan.rowFor(seedUrl)!,
        descriptor(seedUrl, memberOf: [hubUrl]),
      );
      var pending = plan.pending();
      expect(pending, hasLength(1));
      expect(pending.single.siteUrl, hubUrl);
      expect(pending.single.role, DiscoveryRole.hub);
      expect(pending.single.depth, 1);

      // Expansion 2: the hub reached via memberOf expands its members (and
      // its own memberOf — still within the depth cap).
      plan.recordFetched(
        pending.single,
        descriptor(
          hubUrl,
          members: [member(m1Url), member(m2Url)],
          memberOf: [hub2Url],
        ),
      );
      pending = plan.pending();
      expect(pending.map((p) => p.siteUrl), [hub2Url, m1Url, m2Url]);
      expect(pending.every((p) => p.depth == 2), isTrue);
      expect(pending.first.role, DiscoveryRole.hub);
      expect(pending[1].role, DiscoveryRole.leaf);
    });

    test('a third expansion NEVER happens', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      plan.recordFetched(
        plan.rowFor(seedUrl)!,
        descriptor(seedUrl, memberOf: [hubUrl]),
      );
      final hub = plan.pending().single;
      plan.recordFetched(
        hub,
        descriptor(hubUrl, members: [member(m1Url)], memberOf: [hub2Url]),
      );
      // Depth-2 rows: the leaf AND the hub. Both are fetched, but whatever
      // their descriptors claim expands nothing (leaf by role, hub by depth).
      for (final planned in plan.pending()) {
        plan.recordFetched(
          planned,
          descriptor(
            planned.siteUrl,
            members: [member(m3Url)],
            memberOf: ['https://deep.github.io/x/'],
          ),
        );
      }
      expect(plan.pending(), isEmpty);
      expect(plan.discovered.map((p) => p.siteUrl), [hubUrl, hub2Url, m1Url]);
      expect(plan.discovered.map((p) => p.siteUrl), isNot(contains(m3Url)));
      expect(
        plan.discovered.map((p) => p.siteUrl),
        isNot(contains('https://deep.github.io/x/')),
      );
    });

    test("a discovered LEAF's own memberOf/members are never expanded", () {
      final plan = NetworkDiscoveryPlan(seeds: [row(hubUrl)]);
      plan.recordFetched(
        plan.rowFor(hubUrl)!,
        descriptor(hubUrl, members: [member(m1Url)]),
      );
      final leaf = plan.pending().single;
      expect(leaf.role, DiscoveryRole.leaf);
      plan.recordFetched(
        leaf,
        descriptor(m1Url, memberOf: [hub2Url], members: [member(m2Url)]),
      );
      expect(plan.pending(), isEmpty); // §5.6: leaves expand nothing
      expect(plan.discovered.map((p) => p.siteUrl), [m1Url]);
    });
  });

  group('caps and collapsing', () {
    test('the row cap stops discovery and reports truncation', () {
      // maxRows counts seeds + discovered (the run's total row budget).
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)], maxRows: 3);
      plan.recordFetched(
        plan.rowFor(seedUrl)!,
        descriptor(
          seedUrl,
          members: [member(m1Url), member(m2Url), member(m3Url)],
        ),
      );
      expect(plan.discovered, hasLength(2)); // 1 seed + 2 discovered = 3
      expect(plan.discovered.map((p) => p.siteUrl), [m1Url, m2Url]);
      expect(plan.truncated, isTrue);
    });

    test('the production cap is 500 rows per run (§6)', () {
      expect(NetworkDiscoveryPlan.maxRowsPerRun, 500);
      expect(NetworkDiscoveryPlan.maxExpansionDepth, 2);
    });

    test(
      'duplicate URLs collapse — an already-known row is never replanned',
      () {
        final plan = NetworkDiscoveryPlan(
          seeds: [row(seedUrl), row(hubUrl, id: 2, sortOrder: 1)],
        );
        // The seed descriptor lists the OTHER seed as a member and points at
        // a hub that is also a seed; only the genuinely new URL is planned.
        plan.recordFetched(
          plan.rowFor(seedUrl)!,
          descriptor(
            seedUrl,
            members: [member(hubUrl), member(m1Url)],
            memberOf: [hubUrl],
          ),
        );
        expect(plan.discovered.map((p) => p.siteUrl), [m1Url]);
        // The hub keeps its seed role (first role wins) — seeds may expand.
        expect(plan.rowFor(hubUrl)!.role, DiscoveryRole.seed);
        expect(plan.rowFor(hubUrl)!.saved, isNotNull);
        expect(plan.truncated, isFalse);
      },
    );

    test('descriptorUrl resolves library.json under the site root', () {
      final plan = NetworkDiscoveryPlan(
        seeds: [row('https://x.github.io/pitak/')],
      );
      expect(
        plan.pending().single.descriptorUrl,
        'https://x.github.io/pitak/library.json',
      );
    });
  });
}
