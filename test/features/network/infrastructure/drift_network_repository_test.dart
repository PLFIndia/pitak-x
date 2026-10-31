import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';

/// CRUD + merge + constraint tests for [DriftNetworkRepository] over an
/// in-memory database (docs/ARCHITECTURE.md §2: infrastructure tests never hit
/// real storage on disk).
void main() {
  const fpA =
      'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  late AppDatabase db;
  late DriftNetworkRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftNetworkRepository(db);
  });

  tearDown(() async => db.close());

  test('starts empty', () async {
    expect(await repo.loadAll(), isEmpty);
    expect(await repo.count(), 0);
  });

  test('upsert inserts a new row and round-trips every field', () async {
    final saved = (await repo.upsertBySiteUrl(
      NetworkLibrary(
        siteUrl: 'https://a.github.io/lib/',
        name: 'A Library',
        fingerprint: fpA,
        location: GeoPoint.tryCreate(12.99, 77.59),
        precision: LocationPrecision.approximate,
        source: NetworkSource.card,
        isMember: true,
        memberVerified: true,
        listedByHubUrl: 'https://hub.github.io/x/',
        membership: MembershipState.confirmed,
        confirmedByMember: true,
        fetchStatus: FetchStatus.ok,
        fetchedAt: 123,
        createdAt: 456,
        sortOrder: 7,
      ),
    )).toNullable()!;

    expect(saved.id, isNot(0));
    final loaded = (await repo.loadAll()).single;
    expect(loaded.sameAs(saved.copyWith(id: saved.id)), isTrue);
    expect(loaded.siteUrl, 'https://a.github.io/lib/');
    expect(loaded.name, 'A Library');
    expect(loaded.fingerprint, fpA);
    expect(loaded.location!.lat, 12.99);
    expect(loaded.precision, LocationPrecision.approximate);
    expect(loaded.source, NetworkSource.card);
    expect(loaded.isMember, isTrue);
    expect(loaded.memberVerified, isTrue);
    expect(loaded.listedByHubUrl, 'https://hub.github.io/x/');
    expect(loaded.membership, MembershipState.confirmed);
    expect(loaded.confirmedByMember, isTrue);
    expect(loaded.fetchStatus, FetchStatus.ok);
    expect(loaded.fetchedAt, 123);
    expect(loaded.createdAt, 456);
    expect(loaded.sortOrder, 7);
    expect(await repo.count(), 1);
  });

  test('loadAll orders by sortOrder, then name', () async {
    await repo.upsertBySiteUrl(
      const NetworkLibrary(
        siteUrl: 'https://z.github.io/',
        name: 'Zed',
        sortOrder: 2,
      ),
    );
    await repo.upsertBySiteUrl(
      const NetworkLibrary(
        siteUrl: 'https://b.github.io/',
        name: 'Beta',
        sortOrder: 1,
      ),
    );
    await repo.upsertBySiteUrl(
      const NetworkLibrary(
        siteUrl: 'https://a.github.io/',
        name: 'Alpha',
        sortOrder: 1,
      ),
    );
    final names = (await repo.loadAll()).map((r) => r.name).toList();
    expect(names, ['Alpha', 'Beta', 'Zed']);
  });

  group('upsert merge contract', () {
    test('the same siteUrl merges into ONE row', () async {
      await repo.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: 'https://a.github.io/lib/',
          name: 'First',
          sortOrder: 3,
          createdAt: 100,
        ),
      );
      final merged = (await repo.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: 'https://a.github.io/lib/',
          name: 'Second',
          fingerprint: fpA,
        ),
      )).toNullable()!;

      expect(await repo.count(), 1);
      expect(merged.name, 'Second');
      expect(merged.fingerprint, fpA);
      // Identity bookkeeping stays the STORED values.
      expect(merged.createdAt, 100);
      expect(merged.sortOrder, 3);
      expect(merged.id, isNot(0));
    });

    test('incoming nulls never clear stored values', () async {
      await repo.upsertBySiteUrl(
        NetworkLibrary(
          siteUrl: 'https://a.github.io/lib/',
          name: 'Named',
          fingerprint: fpA,
          location: GeoPoint.tryCreate(1.5, 2.5),
          precision: LocationPrecision.exact,
          listedByHubUrl: 'https://hub.github.io/x/',
          fetchedAt: 999,
          fetchStatus: FetchStatus.ok,
        ),
      );
      // An incoming row that "knows nothing" (all nullables null, blank name)
      // must leave the stored knowledge intact.
      final merged = (await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: 'https://a.github.io/lib/'),
      )).toNullable()!;

      expect(merged.name, 'Named'); // blank incoming keeps stored
      expect(merged.fingerprint, fpA);
      expect(merged.location, isNotNull);
      expect(merged.precision, LocationPrecision.exact);
      expect(merged.listedByHubUrl, 'https://hub.github.io/x/');
      expect(merged.fetchedAt, 999);
    });

    test(
      'a manual upsert never touches the stored confirmedByMember flag',
      () async {
        // The flag is refresh-computed proof of the reciprocal link; a manual
        // merge (add-by-URL / card scan of the same address) must keep it.
        await repo.upsertBySiteUrl(
          const NetworkLibrary(
            siteUrl: 'https://a.github.io/lib/',
            listedByHubUrl: 'https://hub.github.io/x/',
            confirmedByMember: true,
            source: NetworkSource.discovered,
          ),
        );
        final merged = (await repo.upsertBySiteUrl(
          const NetworkLibrary(siteUrl: 'https://a.github.io/lib/'),
        )).toNullable()!;
        expect(merged.confirmedByMember, isTrue);
        expect((await repo.loadAll()).single.confirmedByMember, isTrue);
      },
    );

    test('incoming values DO overwrite stored ones', () async {
      await repo.upsertBySiteUrl(
        NetworkLibrary(
          siteUrl: 'https://a.github.io/lib/',
          location: GeoPoint.tryCreate(1.5, 2.5),
          precision: LocationPrecision.exact,
        ),
      );
      final merged = (await repo.upsertBySiteUrl(
        NetworkLibrary(
          siteUrl: 'https://a.github.io/lib/',
          location: GeoPoint.tryCreate(9.25, 8.75),
          precision: LocationPrecision.approximate,
          fetchStatus: FetchStatus.unreachable,
        ),
      )).toNullable()!;
      expect(merged.location!.lat, 9.25);
      expect(merged.precision, LocationPrecision.approximate);
      expect(merged.fetchStatus, FetchStatus.unreachable);
    });
  });

  test('removeById deletes; a missing id is a no-op success', () async {
    final saved = (await repo.upsertBySiteUrl(
      const NetworkLibrary(siteUrl: 'https://a.github.io/'),
    )).toNullable()!;
    expect((await repo.removeById(saved.id)).isRight(), isTrue);
    expect(await repo.count(), 0);
    expect((await repo.removeById(4242)).isRight(), isTrue);
  });

  test('replaceAll swaps the whole table, keeping explicit ids', () async {
    await repo.upsertBySiteUrl(
      const NetworkLibrary(siteUrl: 'https://old.github.io/'),
    );
    final result = await repo.replaceAll([
      const NetworkLibrary(id: 11, siteUrl: 'https://x.github.io/', name: 'X'),
      const NetworkLibrary(id: 12, siteUrl: 'https://y.github.io/', name: 'Y'),
    ]);
    expect(result.isRight(), isTrue);
    final rows = await repo.loadAll();
    expect(rows.map((r) => r.id), [11, 12]);
    expect(rows.map((r) => r.name), ['X', 'Y']);
  });

  test(
    'applyRefresh updates wholesale (may clear) and inserts discoveries',
    () async {
      final seeded = (await repo.upsertBySiteUrl(
        NetworkLibrary(
          siteUrl: 'https://a.github.io/',
          name: 'A',
          location: GeoPoint.tryCreate(1.5, 2.5),
          precision: LocationPrecision.exact,
        ),
      )).toNullable()!;

      // The refresh computed a row that deliberately DROPS the location
      // (e.g. the library turned sharing off): wholesale write honours it.
      final result = await repo.applyRefresh(
        [seeded.copyWith(name: 'A new', clearLocation: true)],
        [
          const NetworkLibrary(
            siteUrl: 'https://d.github.io/',
            name: 'Discovered',
            source: NetworkSource.discovered,
            listedByHubUrl: 'https://a.github.io/',
          ),
        ],
      );
      expect(result.isRight(), isTrue);
      // No baselines ⇒ unconditional write: everything counts as applied.
      final counts = result.toNullable()!;
      expect(counts.applied, 1);
      expect(counts.inserted, 1);
      expect(counts.keptLocal, 0);
      expect(counts.skippedExisting, 0);

      final rows = await repo.loadAll();
      expect(rows, hasLength(2));
      final a = rows.firstWhere((r) => r.siteUrl == 'https://a.github.io/');
      expect(a.name, 'A new');
      expect(a.location, isNull);
      expect(a.precision, isNull);
      final d = rows.firstWhere((r) => r.siteUrl == 'https://d.github.io/');
      expect(d.source, NetworkSource.discovered);
      expect(d.listedByHubUrl, 'https://a.github.io/');
    },
  );

  test('applyRefresh SKIPS a discovered row whose siteUrl the user saved '
      'mid-run — the rest of the run still lands', () async {
    // The user added d.github.io (by URL) while the refresh was fetching.
    final mine = (await repo.upsertBySiteUrl(
      const NetworkLibrary(siteUrl: 'https://d.github.io/', name: 'Mine'),
    )).toNullable()!;
    final seeded = (await repo.upsertBySiteUrl(
      const NetworkLibrary(siteUrl: 'https://a.github.io/', sortOrder: 1),
    )).toNullable()!;

    final result = await repo.applyRefresh(
      [seeded.copyWith(name: 'A fetched')],
      [
        const NetworkLibrary(
          siteUrl: 'https://d.github.io/', // collides with the user's row
          name: 'Discovered',
          source: NetworkSource.discovered,
        ),
      ],
    );

    expect(result.isRight(), isTrue, reason: 'UNIQUE(site_url) not tripped');
    expect(result.toNullable()!.skippedExisting, 1);
    expect(result.toNullable()!.inserted, 0);
    final rows = await repo.loadAll();
    expect(rows, hasLength(2));
    final d = rows.firstWhere((r) => r.siteUrl == 'https://d.github.io/');
    expect(d.id, mine.id);
    expect(d.name, 'Mine', reason: "the user's row wins");
    expect(d.source, NetworkSource.bookmark);
    final a = rows.firstWhere((r) => r.siteUrl == 'https://a.github.io/');
    expect(a.name, 'A fetched', reason: 'the update part still applied');
  });

  group('M1: a refresh never overwrites an edit made while it ran', () {
    test(
      'a row EDITED mid-run is kept, not overwritten — and counted',
      () async {
        // The run read this row (baseline) with no membership…
        final baseline = (await repo.upsertBySiteUrl(
          const NetworkLibrary(siteUrl: 'https://a.github.io/', name: 'A'),
        )).toNullable()!;
        // … and the user CONFIRMED the membership prompt while the run was
        // still fetching (upsert is the controller's write path).
        await repo.upsertBySiteUrl(
          const NetworkLibrary(
            siteUrl: 'https://a.github.io/',
            membership: MembershipState.confirmed,
          ),
        );

        // The run finishes, carrying the stale decision (pending) it computed
        // from the baseline.
        final result = (await repo.applyRefresh(
          [baseline.copyWith(membership: MembershipState.pending)],
          const [],
          baselines: [baseline],
        )).toNullable()!;

        final stored = (await repo.loadAll()).single;
        expect(
          stored.membership,
          MembershipState.confirmed,
          reason:
              "the user's edit wins — the stale snapshot must not revert it",
        );
        expect(stored.name, 'A', reason: 'nothing else on the row moved');
        expect(result.keptLocal, 1);
        expect(result.applied, 0);
      },
    );

    test('a row DELETED mid-run is not resurrected', () async {
      final baseline = (await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: 'https://a.github.io/', name: 'A'),
      )).toNullable()!;
      await repo.removeById(baseline.id);

      final result = (await repo.applyRefresh(
        [baseline.copyWith(name: 'Fetched name')],
        const [],
        baselines: [baseline],
      )).toNullable()!;

      expect(await repo.loadAll(), isEmpty);
      expect(result.applied, 0);
      expect(result.keptLocal, 0);
    });

    test('an UNCHANGED baseline still applies (regression guard for the '
        'normal path)', () async {
      final baseline = (await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: 'https://a.github.io/', name: 'A'),
      )).toNullable()!;

      final result = (await repo.applyRefresh(
        [baseline.copyWith(name: 'A fetched', fetchedAt: 42)],
        const [],
        baselines: [baseline],
      )).toNullable()!;

      final stored = (await repo.loadAll()).single;
      expect(stored.name, 'A fetched');
      expect(stored.fetchedAt, 42);
      expect(result.applied, 1);
      expect(result.keptLocal, 0);
    });

    test('a baseline for a row not in the update list is simply unused; '
        'an empty baseline list writes unconditionally', () async {
      final baseline = (await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: 'https://a.github.io/', name: 'A'),
      )).toNullable()!;
      // Edit mid-run WITHOUT passing the baseline: legacy behaviour (the
      // import path has no snapshot) must still write.
      await repo.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: 'https://a.github.io/',
          membership: MembershipState.confirmed,
        ),
      );
      final result = (await repo.applyRefresh([
        baseline.copyWith(membership: MembershipState.pending),
      ], const [])).toNullable()!;
      final stored = (await repo.loadAll()).single;
      expect(stored.membership, MembershipState.pending);
      expect(result.applied, 1);
    });
  });

  group('constraints', () {
    test('fingerprint is unique among non-null values', () async {
      final first = await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: 'https://a.github.io/', fingerprint: fpA),
      );
      expect(first.isRight(), isTrue);

      final clash = await repo.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: 'https://b.github.io/',
          fingerprint: fpA, // same identity, different URL
        ),
      );
      expect(clash.isLeft(), isTrue, reason: 'UNIQUE(fingerprint) must refuse');
    });

    test('any number of rows may have a NULL fingerprint', () async {
      for (final host in ['a', 'b', 'c']) {
        final r = await repo.upsertBySiteUrl(
          NetworkLibrary(siteUrl: 'https://$host.github.io/'),
        );
        expect(r.isRight(), isTrue);
      }
      expect(await repo.count(), 3);
    });

    test('siteUrl is unique — a direct duplicate insert is refused', () async {
      await db
          .into(db.networkLibraries)
          .insert(
            NetworkLibrariesCompanion.insert(
              siteUrl: 'https://a.github.io/',
              source: 'bookmark',
              createdAt: 1,
              sortOrder: 1,
            ),
          );
      expect(
        () => db
            .into(db.networkLibraries)
            .insert(
              NetworkLibrariesCompanion.insert(
                siteUrl: 'https://a.github.io/',
                source: 'bookmark',
                createdAt: 2,
                sortOrder: 2,
              ),
            ),
        throwsA(anything),
      );
    });
  });

  test(
    'unknown enum tokens from a future build degrade to safe defaults',
    () async {
      // Simulate a row written by a NEWER app version: tokens this build does
      // not know must not crash the read, and must fail closed (bookmark /
      // none / never — the least-privileged readings).
      await db.customUpdate(
        'INSERT INTO network_libraries (site_url, name, source, membership, '
        'fetch_status, created_at, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        variables: const [
          Variable('https://f.github.io/'),
          Variable('Future'),
          Variable('timeTravel'),
          Variable('ascended'),
          Variable('quantum'),
          Variable(5),
          Variable(1),
        ],
      );
      final row = (await repo.loadAll()).single;
      expect(row.source, NetworkSource.bookmark);
      expect(row.membership, MembershipState.none);
      expect(row.fetchStatus, FetchStatus.never);
    },
  );

  test('coordinates without a valid precision label do not surface', () async {
    // Privacy rule shared with the entity JSON parser: a stored pin whose
    // precision token is unreadable is dropped rather than shown as exact.
    await db.customUpdate(
      'INSERT INTO network_libraries (site_url, name, lat, lng, precision, '
      'source, created_at, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: const [
        Variable('https://p.github.io/'),
        Variable('P'),
        Variable(12.5),
        Variable(77.5),
        Variable('ultra'),
        Variable('bookmark'),
        Variable(5),
        Variable(1),
      ],
    );
    final row = (await repo.loadAll()).single;
    expect(row.location, isNull);
    expect(row.precision, isNull);
  });

  group('acceptLibraryMove (C10/R17: one transactional merge)', () {
    const oldSite = 'https://old.github.io/lib/';
    const newSite = 'https://new.github.io/lib/';

    Future<(NetworkLibrary, NetworkLibrary)> seedPair() async {
      final canonical = (await repo.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: oldSite,
          name: 'Saved',
          fingerprint: fpA,
          isMember: true,
          membership: MembershipState.confirmed,
          createdAt: 42,
          sortOrder: 9,
        ),
      )).toNullable()!;
      final placeholder = (await repo.upsertBySiteUrl(
        const NetworkLibrary(siteUrl: newSite, createdAt: 50, sortOrder: 10),
      )).toNullable()!;
      return (canonical, placeholder);
    }

    test(
      'use-new: deletes the duplicate and repoints the canonical row',
      () async {
        final (canonical, placeholder) = await seedPair();
        final next = canonical.copyWith(siteUrl: newSite, name: 'Fresh');

        final result = await repo.acceptLibraryMove(
          canonicalBaseline: canonical,
          canonicalNext: next,
          placeholderBaseline: placeholder,
        );

        final applied = result.toNullable()!;
        expect(applied.repointed, isTrue);
        expect(applied.deletedPlaceholder, isTrue);
        final rows = await repo.loadAll();
        expect(rows, hasLength(1));
        expect(rows.single.id, canonical.id, reason: 'canonical id survives');
        expect(rows.single.siteUrl, newSite);
        expect(rows.single.name, 'Fresh');
        expect(rows.single.sortOrder, 9);
        expect(rows.single.membership, MembershipState.confirmed);
      },
    );

    test('keep-saved: deletes the duplicate without repointing', () async {
      final (canonical, placeholder) = await seedPair();
      final next = canonical.copyWith(name: 'Fresh');

      final result = await repo.acceptLibraryMove(
        canonicalBaseline: canonical,
        canonicalNext: next,
        placeholderBaseline: placeholder,
      );

      expect(result.toNullable()!.repointed, isFalse);
      final rows = await repo.loadAll();
      expect(rows, hasLength(1));
      expect(rows.single.siteUrl, oldSite);
      expect(rows.single.name, 'Fresh');
    });

    test(
      'a card offer (no placeholder row) only updates the canonical row',
      () async {
        final (canonical, _) = await seedPair();
        await repo.removeById(
          (await repo.loadAll()).firstWhere((r) => r.siteUrl == newSite).id,
        );
        final next = canonical.copyWith(siteUrl: newSite);

        final result = await repo.acceptLibraryMove(
          canonicalBaseline: canonical,
          canonicalNext: next,
        );

        expect(result.toNullable()!.deletedPlaceholder, isFalse);
        final rows = await repo.loadAll();
        expect(rows, hasLength(1));
        expect(rows.single.siteUrl, newSite);
      },
    );

    test('SECURITY: a concurrent local edit aborts the whole write', () async {
      final (canonical, placeholder) = await seedPair();
      // The user changed the row (e.g. confirmed membership) while the
      // decision was on screen; the baseline no longer matches.
      await repo.upsertBySiteUrl(canonical.copyWith(name: 'Edited by user'));
      final next = canonical.copyWith(siteUrl: newSite);

      final result = await repo.acceptLibraryMove(
        canonicalBaseline: canonical,
        canonicalNext: next,
        placeholderBaseline: placeholder,
      );

      expect(result.swap().toNullable(), isA<StaleStateFailure>());
      final rows = await repo.loadAll();
      expect(rows, hasLength(2), reason: 'nothing deleted, nothing repointed');
      expect(rows.firstWhere((r) => r.siteUrl == newSite).id, placeholder.id);
    });

    test(
      'SECURITY: a deleted duplicate aborts instead of half-applying',
      () async {
        final (canonical, placeholder) = await seedPair();
        await repo.removeById(placeholder.id);

        final result = await repo.acceptLibraryMove(
          canonicalBaseline: canonical,
          canonicalNext: canonical.copyWith(siteUrl: newSite),
          placeholderBaseline: placeholder,
        );

        expect(result.swap().toNullable(), isA<StaleStateFailure>());
        expect((await repo.loadAll()).single.siteUrl, oldSite);
      },
    );

    test(
      'SECURITY: a row added at the target address meanwhile wins',
      () async {
        final (canonical, placeholder) = await seedPair();
        await repo.removeById(placeholder.id);
        final squatter = (await repo.upsertBySiteUrl(
          const NetworkLibrary(siteUrl: newSite, name: 'Added meanwhile'),
        )).toNullable()!;

        final result = await repo.acceptLibraryMove(
          canonicalBaseline: canonical,
          canonicalNext: canonical.copyWith(siteUrl: newSite),
        );

        expect(result.swap().toNullable(), isA<StaleStateFailure>());
        final rows = await repo.loadAll();
        expect(rows, hasLength(2));
        expect(rows.firstWhere((r) => r.siteUrl == newSite).id, squatter.id);
      },
    );
  });
}
