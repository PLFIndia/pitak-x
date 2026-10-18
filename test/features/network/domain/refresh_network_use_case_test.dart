import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Algorithm tests for [RefreshNetworkUseCase] (libNetwork.md §5.6, §7 S4):
/// apply rules, refusal mapping, D12 conflict handling, membership signals,
/// discovery inserts, cancellation and the ONE-transaction write. Everything
/// runs on fakes — no HTTP, no Drift.
void main() {
  // 64-char lowercase-hex fingerprints (valid per §3.3, readable in tests).
  const fpA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fpB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const fpOwn =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

  const seedUrl = 'https://seed.github.io/pitak/';
  const seed2Url = 'https://seed2.github.io/pitak/';
  const hubUrl = 'https://hub.github.io/pitak/';
  const m1Url = 'https://m1.github.io/pitak/';

  String descriptorUrlOf(String siteUrl) =>
      Uri.parse(siteUrl).resolve('library.json').toString();

  LibraryDescriptor descriptor(
    String siteUrl, {
    String fingerprint = fpA,
    String name = 'Fetched Name',
    GeoPoint? location,
    LocationPrecision? precision,
    List<MemberEntry> members = const [],
    List<String> memberOf = const [],
  }) => LibraryDescriptor(
    fingerprint: fingerprint,
    name: name,
    siteUrl: siteUrl,
    updatedAt: 1,
    location: location,
    precision: precision,
    members: members,
    memberOf: memberOf,
  );

  late _FakeRepo repo;
  late _FakeFetcher fetcher;
  var now = 1000;

  setUp(() {
    repo = _FakeRepo();
    fetcher = _FakeFetcher();
    now = 1000;
  });

  RefreshNetworkUseCase useCase({int concurrency = 1}) => RefreshNetworkUseCase(
    repository: repo,
    fetchDescriptor: fetcher.call,
    clock: () => now,
    concurrency: concurrency,
  );

  NetworkLibrary rowAfter(String siteUrl) =>
      repo.rows.firstWhere((r) => r.siteUrl == siteUrl);

  group('applying fetched descriptors (§5.6 step 2)', () {
    test('ok sets name, fingerprint, location, fetchedAt and status', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl, sortOrder: 1)];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(
          seedUrl,
          name: 'Seed Library',
          location: GeoPoint.tryCreate(12.5, 77.5),
          precision: LocationPrecision.approximate,
        ),
      );

      final report = (await useCase()()).toNullable()!;

      expect(report.fetched, 1);
      expect(report.cancelled, isFalse);
      final row = rowAfter(seedUrl);
      expect(row.name, 'Seed Library');
      expect(row.fingerprint, fpA);
      expect(row.location!.lat, 12.5);
      expect(row.precision, LocationPrecision.approximate);
      expect(row.fetchStatus, FetchStatus.ok);
      expect(row.fetchedAt, 1000);
      // Identity bookkeeping is never touched by a refresh.
      expect(row.id, 1);
      expect(row.sortOrder, 1);
      expect(repo.applyCalls, hasLength(1)); // ONE transaction (§5.6 step 5)
    });

    test(
      'a descriptor without location CLEARS a stored pin (sharing off)',
      () async {
        repo.rows = [
          NetworkLibrary(
            id: 1,
            siteUrl: seedUrl,
            name: 'Old Name',
            fingerprint: fpA,
            location: GeoPoint.tryCreate(12.5, 77.5),
            precision: LocationPrecision.exact,
            fetchStatus: FetchStatus.ok,
            fetchedAt: 500,
          ),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl, name: 'New Name'),
        );

        await useCase()();

        final row = rowAfter(seedUrl);
        expect(row.location, isNull); // handoff §3: clearLocation on wholesale
        expect(row.precision, isNull);
        expect(row.name, 'New Name');
        expect(row.fetchedAt, 1000);
      },
    );

    test(
      'a member row verifies when the published fingerprint matches',
      () async {
        repo.rows = [
          const NetworkLibrary(
            id: 1,
            siteUrl: seedUrl,
            fingerprint: fpA,
            source: NetworkSource.card,
            isMember: true,
          ),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl),
        );

        await useCase()();

        final row = rowAfter(seedUrl);
        expect(row.memberVerified, isTrue);
        expect(row.isMember, isTrue);
        expect(row.fetchStatus, FetchStatus.ok);
      },
    );

    test(
      'an unverified row stays unverified when a fetch supplies the fp',
      () async {
        // The row had NO fingerprint (added by URL); the fetch supplies one —
        // that is not a card-scan match, so memberVerified must stay false.
        repo.rows = [
          const NetworkLibrary(id: 1, siteUrl: seedUrl, isMember: true),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl),
        );

        await useCase()();
        expect(rowAfter(seedUrl).memberVerified, isFalse);
      },
    );
  });

  group('refusal mapping (§5.6 step 2)', () {
    Future<NetworkLibrary> refuseWith(DescriptorRefusal refusal) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          name: 'Cached Name',
          fingerprint: fpA,
          location: GeoPoint.tryCreate(12.5, 77.5),
          precision: LocationPrecision.exact,
          fetchStatus: FetchStatus.ok,
          fetchedAt: 500,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorRefused(refusal);
      await useCase()();
      return rowAfter(seedUrl);
    }

    test('transport-ish refusals map to unreachable', () async {
      for (final refusal in [
        DescriptorRefusal.disallowedUrl,
        DescriptorRefusal.redirectRefused,
        DescriptorRefusal.tooManyRedirects,
        DescriptorRefusal.httpStatus,
        DescriptorRefusal.tooLarge,
        DescriptorRefusal.timedOut,
        DescriptorRefusal.transport,
      ]) {
        final row = await refuseWith(refusal);
        expect(row.fetchStatus, FetchStatus.unreachable, reason: '$refusal');
      }
    });

    test('invalid maps to invalid, schemaTooNew to schemaTooNew', () async {
      expect(
        (await refuseWith(DescriptorRefusal.invalid)).fetchStatus,
        FetchStatus.invalid,
      );
      expect(
        (await refuseWith(DescriptorRefusal.schemaTooNew)).fetchStatus,
        FetchStatus.schemaTooNew,
      );
    });

    test(
      'a refusal never erases cached data (offline keeps pins + names)',
      () async {
        final row = await refuseWith(DescriptorRefusal.transport);
        expect(row.name, 'Cached Name');
        expect(row.fingerprint, fpA);
        expect(row.location, isNotNull);
        expect(row.fetchedAt, 500); // last SUCCESSFUL fetch stays
      },
    );

    test('a refusal does not demote a known identity conflict', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          fingerprint: fpA,
          fetchStatus: FetchStatus.identityConflict,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = const DescriptorRefused(
        DescriptorRefusal.transport,
      );
      await useCase()();
      // The badge must not flicker away because the site went offline.
      expect(rowAfter(seedUrl).fetchStatus, FetchStatus.identityConflict);
    });

    test('report counts refusals by class', () async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: seedUrl),
        const NetworkLibrary(id: 2, siteUrl: seed2Url, sortOrder: 1),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = const DescriptorRefused(
        DescriptorRefusal.timedOut,
      );
      fetcher.results[descriptorUrlOf(seed2Url)] = const DescriptorRefused(
        DescriptorRefusal.invalid,
      );

      final report = (await useCase()()).toNullable()!;
      expect(report.unreachable, 1);
      expect(report.invalid, 1);
      expect(report.fetched, 0);
    });
  });

  group('identity conflicts (D12)', () {
    test(
      'SECURITY: a fetched fp contradicting the stored one flags the row and '
      'updates NOTHING else',
      () async {
        repo.rows = [
          const NetworkLibrary(
            id: 1,
            siteUrl: seedUrl,
            name: 'Old Name',
            fingerprint: fpA,
          ),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(
            seedUrl,
            fingerprint: fpB,
            name: 'Hostile Name',
            location: GeoPoint.tryCreate(1, 2),
            precision: LocationPrecision.exact,
            members: [const MemberEntry(fingerprint: fpOwn, siteUrl: m1Url)],
          ),
        );

        final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;

        final row = rowAfter(seedUrl);
        expect(row.fetchStatus, FetchStatus.identityConflict);
        expect(row.name, 'Old Name'); // nothing else updated …
        expect(row.fingerprint, fpA); // … especially not the identity …
        expect(row.location, isNull); // … nor a hostile pin …
        expect(row.fetchedAt, isNull); // … nor a success stamp.
        expect(row.membership, MembershipState.none); // no membership either
        expect(report.conflicts, 1);
        expect(report.pendingMemberships, 0);
      },
    );

    test('SECURITY: a fetched fp belonging to ANOTHER row flags a cross-row '
        'conflict', () async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: seedUrl, fingerprint: fpA),
        const NetworkLibrary(id: 2, siteUrl: seed2Url, sortOrder: 1),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(seedUrl, name: 'First'),
      );
      fetcher.results[descriptorUrlOf(seed2Url)] = DescriptorFetched(
        descriptor(seed2Url, name: 'Impostor'), // publishes fpA too
      );

      final report = (await useCase()()).toNullable()!;

      expect(rowAfter(seedUrl).fetchStatus, FetchStatus.ok);
      final second = rowAfter(seed2Url);
      expect(second.fetchStatus, FetchStatus.identityConflict);
      expect(second.fingerprint, isNull); // never merged
      expect(second.name, ''); // nothing else updated
      expect(report.conflicts, 1);
    });
  });

  group('own membership (§5.6 step 4)', () {
    final listsMe = DescriptorFetched(
      descriptor(
        seedUrl,
        members: [
          const MemberEntry(
            fingerprint: fpOwn,
            siteUrl: 'https://me.github.io/',
          ),
        ],
      ),
    );

    test('own fingerprint in members ⇒ pending + report count', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
      fetcher.results[descriptorUrlOf(seedUrl)] = listsMe;

      final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;

      expect(rowAfter(seedUrl).membership, MembershipState.pending);
      expect(report.pendingMemberships, 1);
    });

    test('declined is NEVER re-prompted', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          membership: MembershipState.declined,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = listsMe;

      final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;

      expect(rowAfter(seedUrl).membership, MembershipState.declined);
      expect(report.pendingMemberships, 0);
    });

    test('pending stays pending without double-counting', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          membership: MembershipState.pending,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = listsMe;

      final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;
      expect(rowAfter(seedUrl).membership, MembershipState.pending);
      expect(report.pendingMemberships, 0);
    });

    test(
      'a confirmed hub that dropped me is reported, state unchanged',
      () async {
        repo.rows = [
          const NetworkLibrary(
            id: 1,
            siteUrl: seedUrl,
            membership: MembershipState.confirmed,
          ),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl, members: []), // no longer lists me
        );

        final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;

        expect(rowAfter(seedUrl).membership, MembershipState.confirmed);
        expect(report.noLongerListed, [seedUrl]);
      },
    );

    test('a confirmed hub still listing me changes nothing', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          membership: MembershipState.confirmed,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = listsMe;

      final report = (await useCase()(ownFingerprint: fpOwn)).toNullable()!;
      expect(report.noLongerListed, isEmpty);
      expect(report.pendingMemberships, 0);
    });

    test('SECURITY: an invalid own fingerprint disables detection', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
      fetcher.results[descriptorUrlOf(seedUrl)] = listsMe;

      final report = (await useCase()(
        ownFingerprint: 'not-a-fingerprint',
      )).toNullable()!;
      expect(rowAfter(seedUrl).membership, MembershipState.none);
      expect(report.pendingMemberships, 0);
    });
  });

  group('discovery (§5.6 step 3)', () {
    test(
      'discovered rows are inserted with hints, hub link and order',
      () async {
        repo.rows = [
          const NetworkLibrary(id: 1, siteUrl: seedUrl, sortOrder: 3),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(
            seedUrl,
            members: [
              const MemberEntry(
                fingerprint: fpB,
                siteUrl: m1Url,
                name: 'Member One',
              ),
            ],
            memberOf: [hubUrl],
          ),
        );
        fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
          descriptor(hubUrl, name: 'The Hub', fingerprint: fpOwn),
        );
        fetcher.results[descriptorUrlOf(m1Url)] = const DescriptorRefused(
          DescriptorRefusal.httpStatus,
        );

        final report = (await useCase()()).toNullable()!;

        expect(report.discovered, 2);
        expect(repo.applyCalls, hasLength(1)); // still ONE transaction
        expect(repo.applyCalls.single.$1, hasLength(1)); // the seed update
        final inserted = repo.applyCalls.single.$2;
        expect(inserted, hasLength(2));

        // memberOf hubs first (planner order), sortOrder appended after mine.
        final hub = inserted.firstWhere((r) => r.siteUrl == hubUrl);
        expect(hub.source, NetworkSource.discovered);
        expect(hub.name, 'The Hub'); // from its OWN successful fetch
        expect(hub.fingerprint, fpOwn);
        expect(hub.fetchStatus, FetchStatus.ok);
        expect(hub.listedByHubUrl, isNull); // hubs are not "listed by"
        expect(hub.sortOrder, 4);

        // The member keeps the hub's NAME hint even though its own fetch
        // failed — but NOT the hub's fingerprint claim (H1): a fingerprint
        // becomes a fact only through the member's own fetch or a card scan.
        final member = inserted.firstWhere((r) => r.siteUrl == m1Url);
        expect(member.source, NetworkSource.discovered);
        expect(member.name, 'Member One');
        expect(member.fingerprint, isNull);
        expect(member.listedByHubUrl, seedUrl);
        expect(member.fetchStatus, FetchStatus.unreachable);
        expect(member.sortOrder, 5);
        expect(member.createdAt, 1000);
      },
    );

    test('a member whose own fetch AGREES with the hub entry adopts the '
        'fingerprint from its own descriptor', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(
          seedUrl,
          members: [const MemberEntry(fingerprint: fpB, siteUrl: m1Url)],
        ),
      );
      fetcher.results[descriptorUrlOf(m1Url)] = DescriptorFetched(
        descriptor(m1Url, fingerprint: fpB, name: 'Member One'),
      );

      final report = (await useCase()()).toNullable()!;

      final member = rowAfter(m1Url);
      expect(member.fingerprint, fpB);
      expect(member.name, 'Member One');
      expect(member.fetchStatus, FetchStatus.ok);
      expect(report.conflicts, 0);
    });

    test('SECURITY: a member whose published fp contradicts the hub entry is '
        'flagged, not merged — and the hub claim is NOT stored', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(
          seedUrl,
          members: [
            // The hub vouches: "fpB lives at m1".
            const MemberEntry(fingerprint: fpB, siteUrl: m1Url),
          ],
        ),
      );
      fetcher.results[descriptorUrlOf(m1Url)] = DescriptorFetched(
        // … but m1 itself publishes a DIFFERENT identity.
        descriptor(m1Url, fingerprint: fpOwn, name: 'Someone Else'),
      );

      final report = (await useCase()()).toNullable()!;

      final member = rowAfter(m1Url);
      expect(member.fetchStatus, FetchStatus.identityConflict);
      expect(member.fingerprint, isNull); // neither claim is adopted
      expect(member.name, '');
      expect(report.conflicts, 1);
    });

    group('SECURITY (H1): hub claims can never break the ONE transaction', () {
      const m2Url = 'https://m2.github.io/pitak/';

      test('a hub listing ONE fingerprint at TWO addresses does not insert '
          'duplicate fingerprints', () async {
        repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(
            seedUrl,
            members: [
              const MemberEntry(fingerprint: fpB, siteUrl: m1Url),
              const MemberEntry(fingerprint: fpB, siteUrl: m2Url), // stale/evil
            ],
          ),
        );
        // Neither member answers — before H1 both rows were inserted with
        // fpB and UNIQUE(fingerprint) rolled the whole run back.

        final result = await useCase()();

        expect(result.isRight(), isTrue, reason: 'the run must land');
        expect(repo.rows.where((r) => r.siteUrl == m1Url), hasLength(1));
        expect(repo.rows.where((r) => r.siteUrl == m2Url), hasLength(1));
        expect(rowAfter(m1Url).fingerprint, isNull);
        expect(rowAfter(m2Url).fingerprint, isNull);
        expect(rowAfter(seedUrl).fetchStatus, FetchStatus.ok);
      });

      test('a hub claiming a fingerprint that a SAVED row already owns does '
          'not collide with it', () async {
        repo.rows = [
          const NetworkLibrary(id: 1, siteUrl: seedUrl),
          // The user already saved m1 under its canonical URL; its identity
          // is a stored fact.
          const NetworkLibrary(
            id: 2,
            siteUrl: m1Url,
            fingerprint: fpB,
            sortOrder: 1,
          ),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(
            seedUrl,
            // The hub lists the SAME library at another address.
            members: [const MemberEntry(fingerprint: fpB, siteUrl: m2Url)],
          ),
        );
        fetcher.results[descriptorUrlOf(m1Url)] = DescriptorFetched(
          descriptor(m1Url, fingerprint: fpB),
        );
        fetcher.results[descriptorUrlOf(m2Url)] = DescriptorFetched(
          descriptor(m2Url, fingerprint: fpB), // a mirror of m1's file
        );

        final result = await useCase()();

        expect(result.isRight(), isTrue, reason: 'the run must land');
        expect(rowAfter(m1Url).fingerprint, fpB); // the stored fact stands
        expect(rowAfter(m1Url).fetchStatus, FetchStatus.ok);
        final mirror = rowAfter(m2Url);
        expect(mirror.fingerprint, isNull);
        expect(mirror.fetchStatus, FetchStatus.identityConflict);
      });

      test("a hostile hub cannot pre-own a victim's fingerprint through a "
          'member hint (no order-dependent hijack)', () async {
        // The victim is a fresh bookmark (no stored fp yet); the hostile hub
        // lists an attacker address with the victim's fingerprint, and the
        // attacker's site publishes a copy of the victim's descriptor.
        const victimUrl = 'https://victim.github.io/pitak/';
        const attackerUrl = 'https://evil.github.io/pitak/';
        repo.rows = [
          const NetworkLibrary(id: 1, siteUrl: hubUrl), // hostile hub first
          const NetworkLibrary(id: 2, siteUrl: victimUrl, sortOrder: 1),
        ];
        fetcher.results[descriptorUrlOf(hubUrl)] = DescriptorFetched(
          descriptor(
            hubUrl,
            fingerprint: fpOwn,
            members: [
              const MemberEntry(fingerprint: fpA, siteUrl: attackerUrl),
            ],
          ),
        );
        fetcher.results[descriptorUrlOf(victimUrl)] = DescriptorFetched(
          descriptor(victimUrl, name: 'Victim'),
        );
        fetcher.results[descriptorUrlOf(attackerUrl)] = DescriptorFetched(
          descriptor(attackerUrl, name: 'Victim'),
        );

        final result = await useCase()();

        expect(result.isRight(), isTrue);
        // The hint gave the attacker nothing: the victim (a seed, fetched in
        // round 1) adopted its own fingerprint first; the attacker's leaf
        // (round 2) collides with a this-run adoption of a row that had no
        // stored fp → BOTH are flagged, neither keeps fpA (deterministic).
        // What matters for security: the attacker never silently OWNS fpA.
        final attacker = rowAfter(attackerUrl);
        expect(attacker.fetchStatus, FetchStatus.identityConflict);
        expect(attacker.fingerprint, isNull);
        expect(rowAfter(victimUrl).fingerprint, isNot(fpA));
        expect(rowAfter(victimUrl).fetchStatus, FetchStatus.identityConflict);
      });
    });
  });

  group('determinism under concurrency (M6)', () {
    test('two rows with NO stored fp publishing the same fp are BOTH flagged '
        'and neither adopts it — whichever lands first', () async {
      for (final order in [
        [seedUrl, seed2Url],
        [seed2Url, seedUrl],
      ]) {
        repo = _FakeRepo();
        fetcher = _FakeFetcher();
        repo.rows = [
          NetworkLibrary(id: 1, siteUrl: order[0]),
          NetworkLibrary(id: 2, siteUrl: order[1], sortOrder: 1),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl, name: 'First'),
        );
        fetcher.results[descriptorUrlOf(seed2Url)] = DescriptorFetched(
          descriptor(seed2Url, name: 'Second'), // publishes fpA too
        );

        final report = (await useCase()()).toNullable()!;

        for (final url in [seedUrl, seed2Url]) {
          final row = rowAfter(url);
          expect(row.fetchStatus, FetchStatus.identityConflict, reason: url);
          expect(row.fingerprint, isNull, reason: url);
          expect(row.name, '', reason: '$url: nothing else applied');
        }
        expect(report.conflicts, 2, reason: 'order $order');
      }
    });

    test('a THIRD row publishing a contested fp is flagged as well', () async {
      const thirdUrl = 'https://third.github.io/pitak/';
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: seedUrl),
        const NetworkLibrary(id: 2, siteUrl: seed2Url, sortOrder: 1),
        const NetworkLibrary(id: 3, siteUrl: thirdUrl, sortOrder: 2),
      ];
      for (final url in [seedUrl, seed2Url, thirdUrl]) {
        fetcher.results[descriptorUrlOf(url)] = DescriptorFetched(
          descriptor(url),
        );
      }

      final report = (await useCase()()).toNullable()!;

      expect(report.conflicts, 3);
      expect(repo.rows.every((r) => r.fingerprint == null), isTrue);
    });

    test('a conflict badge turns memberVerified OFF (M11)', () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: seedUrl,
          fingerprint: fpA,
          isMember: true,
          memberVerified: true,
        ),
      ];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(seedUrl, fingerprint: fpB), // the site changed identity
      );

      await useCase()();

      final row = rowAfter(seedUrl);
      expect(row.fetchStatus, FetchStatus.identityConflict);
      expect(row.memberVerified, isFalse);
      expect(row.isMember, isTrue); // the in-person add itself stands
      expect(row.fingerprint, fpA); // the stored fact is kept
    });
  });

  group('cancellation (§5.6 step 1)', () {
    test(
      'cancel between fetches still applies partials in ONE transaction',
      () async {
        var cancelled = false;
        repo.rows = [
          const NetworkLibrary(id: 1, siteUrl: seedUrl),
          const NetworkLibrary(id: 2, siteUrl: seed2Url, sortOrder: 1),
        ];
        fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
          descriptor(seedUrl, name: 'First'),
        );
        // The first fetch flips the switch "from the UI"; the second must then
        // never start (concurrency 1 keeps the order deterministic).
        fetcher.onFetch = (_) => cancelled = true;

        final report = (await useCase()(
          isCancelled: () => cancelled,
        )).toNullable()!;

        expect(fetcher.fetchedUrls, [descriptorUrlOf(seedUrl)]);
        expect(report.cancelled, isTrue);
        expect(report.fetched, 1);
        expect(repo.applyCalls, hasLength(1));
        expect(rowAfter(seedUrl).name, 'First'); // the partial WAS applied
        expect(rowAfter(seed2Url).fetchStatus, FetchStatus.never); // untouched
      },
    );

    test('cancel before the first fetch applies an empty run', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];

      final report = (await useCase()(isCancelled: () => true)).toNullable()!;

      expect(fetcher.fetchedUrls, isEmpty);
      expect(report.cancelled, isTrue);
      expect(repo.applyCalls, hasLength(1));
      expect(repo.applyCalls.single.$1, isEmpty);
      expect(repo.applyCalls.single.$2, isEmpty);
      expect(rowAfter(seedUrl).fetchStatus, FetchStatus.never);
    });
  });

  group('concurrency and failures', () {
    test('at most `concurrency` fetches are in flight', () async {
      repo.rows = [
        for (var i = 0; i < 9; i++)
          NetworkLibrary(
            id: i + 1,
            siteUrl: 'https://lib$i.github.io/pitak/',
            sortOrder: i,
          ),
      ];
      final gate = Completer<void>();
      fetcher.blockUntil = gate.future;
      var unawaited = false;
      final run = useCase(concurrency: 4)().then((r) {
        unawaited = true;
        return r;
      });
      await Future<void>.delayed(Duration.zero); // let the workers start
      expect(fetcher.inFlightPeak, lessThanOrEqualTo(4));
      expect(fetcher.inFlightPeak, greaterThan(1));
      gate.complete();
      await run;
      expect(unawaited, isTrue);
      expect(fetcher.fetchedUrls, hasLength(9));
    });

    test('a storage failure surfaces as Left; nothing else changes', () async {
      repo.rows = [const NetworkLibrary(id: 1, siteUrl: seedUrl)];
      fetcher.results[descriptorUrlOf(seedUrl)] = DescriptorFetched(
        descriptor(seedUrl),
      );
      repo.applyResult = left(const StorageFailure('disk gone'));

      final result = await useCase()();
      expect(result.isLeft(), isTrue);
    });

    test('an empty network refreshes cleanly', () async {
      final report = (await useCase()()).toNullable()!;
      expect(report.fetched, 0);
      expect(report.discovered, 0);
      expect(repo.applyCalls, hasLength(1));
    });
  });
}

/// In-memory repository fake: [applyRefresh] records every call AND applies
/// it the way the Drift implementation would — wholesale updates by id,
/// inserts with fresh ids, a discovered row whose siteUrl already exists is
/// skipped, and the table's two UNIQUE constraints (`site_url`,
/// `fingerprint` among non-null) are ENFORCED: a violation rolls the whole
/// call back and returns a `StorageFailure`, exactly like SQLite would. The
/// H1 regression was invisible while this fake accepted anything.
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  final List<(List<NetworkLibrary>, List<NetworkLibrary>)> applyCalls = [];
  Either<Failure, Unit> applyResult = right(unit);

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, Unit>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered,
  ) async {
    applyCalls.add((List.of(updated), List.of(discovered)));
    if (applyResult.isLeft()) return applyResult;
    // Work on a copy: a constraint violation must leave `rows` untouched
    // (one transaction, rolled back).
    final next = List.of(rows);
    for (final update in updated) {
      final index = next.indexWhere((r) => r.id == update.id);
      if (index >= 0) next[index] = update;
    }
    var nextId = next.fold(0, (max, r) => r.id > max ? r.id : max);
    for (final insert in discovered) {
      if (next.any((r) => r.siteUrl == insert.siteUrl)) continue;
      nextId++;
      next.add(insert.copyWith(id: nextId));
    }
    final fingerprints = <String>{};
    for (final row in next) {
      final fp = row.fingerprint;
      if (fp != null && !fingerprints.add(fp)) {
        return left(
          const StorageFailure('UNIQUE constraint failed: fingerprint'),
        );
      }
    }
    rows = next;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}

/// Scripted fetcher fake keyed by descriptor URL. Unknown URLs answer
/// `httpStatus` (like a site without a library.json). [onFetch] runs at the
/// start of every call (tests flip cancel flags from it); [blockUntil] gates
/// every call (concurrency tests).
class _FakeFetcher {
  final Map<String, DescriptorFetchResult> results = {};
  final List<String> fetchedUrls = [];
  void Function(String url)? onFetch;
  Future<void>? blockUntil;
  int inFlight = 0;
  int inFlightPeak = 0;

  Future<DescriptorFetchResult> call(String url) async {
    fetchedUrls.add(url);
    onFetch?.call(url);
    inFlight++;
    if (inFlight > inFlightPeak) inFlightPeak = inFlight;
    try {
      final gate = blockUntil;
      if (gate != null) await gate;
      return results[url] ??
          const DescriptorRefused(DescriptorRefusal.httpStatus);
    } finally {
      inFlight--;
    }
  }
}
