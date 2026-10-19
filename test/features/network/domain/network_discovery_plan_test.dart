import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_discovery_plan.dart';

/// Policy tests for [NetworkDiscoveryPlan] (docs/ARCHITECTURE.md §3 network, D10). The
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

    test(
      'DETERMINISM (M6): a URL met as a leaf AND named as a hub in one round '
      'is a hub — whichever descriptor landed first',
      () {
        for (final hubFirst in [true, false]) {
          final plan = NetworkDiscoveryPlan(
            seeds: [row(seedUrl), row(hub2Url, id: 2, sortOrder: 1)],
          );
          // seed lists X as a member (leaf); hub2 says "I am a member of X"
          // (so X is a hub). Both are round-1 descriptors.
          final seedDescriptor = descriptor(
            seedUrl,
            members: [member(m1Url, name: 'Listed', fingerprint: 'a' * 64)],
          );
          final hub2Descriptor = descriptor(hub2Url, memberOf: [m1Url]);
          if (hubFirst) {
            plan
              ..recordFetched(plan.rowFor(hub2Url)!, hub2Descriptor)
              ..recordFetched(plan.rowFor(seedUrl)!, seedDescriptor);
          } else {
            plan
              ..recordFetched(plan.rowFor(seedUrl)!, seedDescriptor)
              ..recordFetched(plan.rowFor(hub2Url)!, hub2Descriptor);
          }

          final x = plan.rowFor(m1Url)!;
          expect(x.role, DiscoveryRole.hub, reason: 'hubFirst=$hubFirst');
          expect(x.depth, 1);
          // The leaf facts are merged in EITHER order: the row is still
          // "listed by" the seed and its hints are still checked on fetch.
          expect(x.listedByHubUrl, seedUrl, reason: 'hubFirst=$hubFirst');
          expect(x.hintName, 'Listed', reason: 'hubFirst=$hubFirst');
          expect(x.hintFingerprint, 'a' * 64, reason: 'hubFirst=$hubFirst');
          // And X, now a hub, expands its members when fetched.
          plan.recordFetched(x, descriptor(m1Url, members: [member(m2Url)]));
          expect(plan.rowFor(m2Url), isNotNull, reason: 'hubFirst=$hubFirst');
          expect(plan.discovered, hasLength(2));
        }
      },
    );

    test('a SETTLED leaf is never re-planned as a hub', () {
      final plan = NetworkDiscoveryPlan(
        seeds: [row(seedUrl), row(hub2Url, id: 2, sortOrder: 1)],
      );
      final seed = plan.rowFor(seedUrl)!;
      final hub2 = plan.rowFor(hub2Url)!;
      plan.recordFetched(seed, descriptor(seedUrl, members: [member(m1Url)]));
      // The leaf is fetched (settled) before hub2's descriptor arrives.
      final leaf = plan.rowFor(m1Url)!;
      plan
        ..recordRefused(leaf)
        ..recordFetched(hub2, descriptor(hub2Url, memberOf: [m1Url]));
      expect(plan.rowFor(m1Url)!.role, DiscoveryRole.leaf);
      expect(plan.pending(), isEmpty);
    });

    test(
      'L3: a row promoted to hub WHILE its fetch was in flight expands its '
      'members (expansion follows the CURRENT plan, not the captured row)',
      () {
        final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
        // The seed's descriptor surfaces L as a member (leaf) and H as a hub.
        plan.recordFetched(
          plan.rowFor(seedUrl)!,
          descriptor(seedUrl, members: [member(m1Url)], memberOf: [hubUrl]),
        );
        // The worker captured L's row at round start — a LEAF.
        final capturedLeaf = plan.rowFor(m1Url)!;
        expect(capturedLeaf.role, DiscoveryRole.leaf);

        // While L's fetch was in flight, H's descriptor named L as a hub:
        // the plan merges the role upward (L is not settled yet).
        plan.recordFetched(
          plan.rowFor(hubUrl)!,
          descriptor(hubUrl, memberOf: [m1Url]),
        );
        expect(plan.rowFor(m1Url)!.role, DiscoveryRole.hub);

        // L's own fetch now lands, but the worker still holds the CAPTURED
        // leaf. Expansion must follow the current hub row: L's members are
        // discovered (before the L3 fix this silently expanded nothing).
        plan.recordFetched(
          capturedLeaf,
          descriptor(m1Url, members: [member(m2Url)]),
        );
        expect(plan.rowFor(m2Url), isNotNull);
        expect(plan.rowFor(m2Url)!.role, DiscoveryRole.leaf);
        expect(plan.rowFor(m2Url)!.depth, 2);
        expect(plan.pending().map((p) => p.siteUrl), [m2Url]);
      },
    );

    test('L3 counter-test: a row whose CURRENT role is still leaf expands '
        'nothing — the fix never over-expands (§5.6)', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      plan.recordFetched(
        plan.rowFor(seedUrl)!,
        descriptor(seedUrl, members: [member(m1Url)]),
      );
      final capturedLeaf = plan.rowFor(m1Url)!;
      // No promotion happens before L's own fetch lands: the current plan
      // still says leaf, so its members/memberOf are never expanded.
      plan.recordFetched(
        capturedLeaf,
        descriptor(m1Url, members: [member(m2Url)], memberOf: [hubUrl]),
      );
      expect(plan.rowFor(m2Url), isNull);
      expect(plan.rowFor(hubUrl), isNull);
      expect(plan.pending(), isEmpty);
    });

    test('L3 determinism: with the promotion processed before the row lands, '
        'the captured (stale) row and the current row expand identically', () {
      List<String> urlsOf(NetworkDiscoveryPlan plan) => [
        for (final p in plan.all) '${p.siteUrl}|${p.role.name}',
      ];

      // Run A: the worker hands recordFetched the row it captured at round
      // start (stale — still a leaf instance).
      final a = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      a.recordFetched(
        a.rowFor(seedUrl)!,
        descriptor(seedUrl, members: [member(m1Url)], memberOf: [hubUrl]),
      );
      final captured = a.rowFor(m1Url)!;
      a
        ..recordFetched(
          a.rowFor(hubUrl)!,
          descriptor(hubUrl, memberOf: [m1Url]),
        )
        ..recordFetched(captured, descriptor(m1Url, members: [member(m2Url)]));

      // Run B: same descriptors, same order — but the row handed in is
      // re-read from the plan (what a non-stale worker would hold).
      final b = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      b
        ..recordFetched(
          b.rowFor(seedUrl)!,
          descriptor(seedUrl, members: [member(m1Url)], memberOf: [hubUrl]),
        )
        ..recordFetched(
          b.rowFor(hubUrl)!,
          descriptor(hubUrl, memberOf: [m1Url]),
        )
        ..recordFetched(
          b.rowFor(m1Url)!,
          descriptor(m1Url, members: [member(m2Url)]),
        );

      expect(urlsOf(a), urlsOf(b));
      expect(urlsOf(a), [
        '$seedUrl|seed',
        '$hubUrl|hub',
        '$m1Url|hub',
        '$m2Url|leaf',
      ]);
    });

    test('L3 boundary: a leaf processed BEFORE any promotion still expands '
        'nothing (fail closed — nothing knew it was a hub yet)', () {
      final plan = NetworkDiscoveryPlan(seeds: [row(seedUrl)]);
      plan
        ..recordFetched(
          plan.rowFor(seedUrl)!,
          descriptor(seedUrl, members: [member(m1Url)], memberOf: [hubUrl]),
        )
        // L's descriptor lands FIRST: at processing time the plan honestly
        // has L as a leaf, so it settles without expanding. H's later
        // memberOf claim then meets a settled row and is not re-planned (the
        // settled-row rule above) — this order yields fewer rows by design.
        ..recordFetched(
          plan.rowFor(m1Url)!,
          descriptor(m1Url, members: [member(m2Url)]),
        )
        ..recordFetched(
          plan.rowFor(hubUrl)!,
          descriptor(hubUrl, memberOf: [m1Url]),
        );
      expect(plan.rowFor(m2Url), isNull);
      expect(plan.rowFor(m1Url)!.role, DiscoveryRole.leaf);
    });

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
