import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/a11y.dart';

/// Page tests for the Library network screen (docs/ARCHITECTURE.md §3 network+S4): the
/// Libraries list over the real provider chain (fake repository + fake
/// descriptor fetcher at the edges), removal, add-by-URL, the membership
/// prompt, the refresh flow, distance sorting, the My-card tab, and the
/// a11y trio.
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  final fpB = 'b' * 64; // a second valid fingerprint, readable in tests

  late _FakeRepo repo;
  late DescriptorFetchResult Function(String url) fetchScript;

  Future<void> pumpPage(
    WidgetTester tester, {
    String? publishedUrl,
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'library_id': rawId, ...prefs});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWith((ref) async => repo),
          publishedSiteUrlProvider.overrideWith((ref) async => publishedUrl),
          descriptorFetcherProvider.overrideWithValue(
            (url) async => fetchScript(url),
          ),
        ],
        child: const MaterialApp(home: NetworkPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = _FakeRepo([]);
    // Default: every descriptor fetch 404s (a site without library.json).
    fetchScript = (_) => const DescriptorRefused(DescriptorRefusal.httpStatus);
  });

  testWidgets('empty state explains both add paths', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('No libraries saved yet.'), findsOneWidget);
    expect(
      find.textContaining('Tap "Add bookmark" to save a library'),
      findsOneWidget,
    );
    expect(find.textContaining('"Add member" to scan'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add member'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FloatingActionButton, 'Add bookmark'),
      findsOneWidget,
    );
    // The old app-bar icon is gone — the button replaced it.
    expect(find.byTooltip('Add by URL'), findsNothing);
    expect(find.text('Never refreshed yet.'), findsOneWidget);
  });

  testWidgets('rows render with their badges', (tester) async {
    repo.rows = [
      const NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'Member Library',
        fingerprint: fp,
        source: NetworkSource.card,
        isMember: true,
        memberVerified: true,
      ),
      const NetworkLibrary(
        id: 2,
        siteUrl: 'https://u.github.io/y/',
        name: 'Unverified One',
        source: NetworkSource.card,
        isMember: true,
      ),
      const NetworkLibrary(
        id: 3,
        siteUrl: 'https://c.github.io/z/',
        name: 'Clashing',
        fingerprint: fp,
        fetchStatus: FetchStatus.identityConflict,
      ),
      // Hub-listed AND its own site links back: the reciprocal-consent chip.
      const NetworkLibrary(
        id: 4,
        siteUrl: 'https://d.github.io/w/',
        name: 'Confirmed Member',
        listedByHubUrl: 'https://m.github.io/x/',
        confirmedByMember: true,
      ),
      // Hub-listed but NOT linked back: no chip — the claim alone is not
      // consent.
      const NetworkLibrary(
        id: 5,
        siteUrl: 'https://e.github.io/v/',
        name: 'Claimed Only',
        listedByHubUrl: 'https://m.github.io/x/',
      ),
    ];
    await pumpPage(tester);
    expect(find.text('Member Library'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Identity conflict'), findsOneWidget);
    expect(find.text('https://m.github.io/x/'), findsOneWidget);

    // Off-screen rows need scrollUntilVisible, not ensureVisible: the lazy
    // sliver list has not BUILT them yet, so their finder matches nothing
    // (600 dp test surface). The scrollable must be the LIST's own —
    // find.byType(Scrollable).first would grab the tab view's horizontal
    // PageView and drag us onto another tab.
    final listScrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Unverified One'),
      150,
      scrollable: listScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Unverified'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Confirmed Member'),
      -150, // scroll back up
      scrollable: listScrollable,
    );
    await tester.pumpAndSettle();
    // Exactly one row earns the reciprocal-consent chip ("Claimed Only"
    // lacks the memberOf link-back, so it shows none).
    expect(find.text('Confirmed by member'), findsOneWidget);
  });

  testWidgets('removing a row asks the repository and refreshes the list', (
    tester,
  ) async {
    repo.rows = [
      const NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'Doomed',
      ),
    ];
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Removed.'), findsOneWidget);
    expect(find.text('Doomed'), findsNothing);
  });

  group('add by URL (the "Add bookmark" button)', () {
    testWidgets('a valid link saves a bookmark row and joins the list', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add bookmark'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add a library by URL'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://new.github.io/lib/',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Name (optional)'),
        '  New Library  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        find.text('Library added. Tap Refresh to fetch its details.'),
        findsOneWidget,
      );
      expect(find.text('New Library'), findsOneWidget);
      final saved = repo.upserts.single;
      expect(saved.siteUrl, 'https://new.github.io/lib/');
      expect(saved.name, 'New Library'); // trimmed
      expect(saved.source, NetworkSource.bookmark);
    });

    testWidgets('a non-Pages link is refused inside the dialog', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add bookmark'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://evil.example.com/',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // The dialog stays open with the plain-words hint; nothing was saved.
      expect(find.text('Add a library by URL'), findsOneWidget);
      expect(
        find.textContaining('Enter a GitHub Pages (github.io)'),
        findsOneWidget,
      );
      expect(repo.upserts, isEmpty);
    });

    testWidgets('an already-saved link collapses with a clear message', (
      tester,
    ) async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: 'https://dup.github.io/x/'),
      ];
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add bookmark'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://dup.github.io/x/',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('That library is already saved.'), findsOneWidget);
      expect(repo.rows, hasLength(1));
    });
  });

  group('membership prompt (§5.6 step 4)', () {
    testWidgets('a pending hub asks, "Show membership" confirms it', (
      tester,
    ) async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://hub.github.io/x/',
          name: 'The Hub',
          membership: MembershipState.pending,
        ),
      ];
      await pumpPage(tester);
      expect(
        find.textContaining("'The Hub' lists you as a member."),
        findsOneWidget,
      );

      // Scroll the button clear of the stacked FABs (600 dp test surface).
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Show membership'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Show membership'));
      await tester.pumpAndSettle();

      expect(repo.upserts.single.membership, MembershipState.confirmed);
      expect(
        find.textContaining('lists you as a member'),
        findsNothing,
      ); // prompt gone
      expect(find.text('My hub'), findsOneWidget); // confirmed badge
    });

    testWidgets('"No" declines without re-prompting (but Reconsider '
        'stays)', (tester) async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://hub.github.io/x/',
          name: 'The Hub',
          membership: MembershipState.pending,
        ),
      ];
      await pumpPage(tester);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'No'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'No'));
      await tester.pumpAndSettle();

      expect(repo.upserts.single.membership, MembershipState.declined);
      expect(find.textContaining('lists you as a member'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Reconsider'), findsOneWidget);
    });

    testWidgets('"Reconsider" re-opens a declined question', (tester) async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://hub.github.io/x/',
          name: 'The Hub',
          membership: MembershipState.declined,
        ),
      ];
      await pumpPage(tester);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Reconsider'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reconsider'));
      await tester.pumpAndSettle();

      expect(repo.upserts.single.membership, MembershipState.pending);
      expect(
        find.textContaining("'The Hub' lists you as a member."),
        findsOneWidget,
      );
    });
  });

  group('refresh flow (D11: user-initiated only)', () {
    testWidgets('nothing is fetched before the user taps Refresh', (
      tester,
    ) async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: 'https://a.github.io/x/'),
      ];
      var fetches = 0;
      fetchScript = (url) {
        fetches++;
        return const DescriptorRefused(DescriptorRefusal.httpStatus);
      };
      await pumpPage(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(fetches, 0);
    });

    testWidgets('Refresh fetches, applies, stamps and summarizes', (
      tester,
    ) async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: 'https://a.github.io/x/'),
      ];
      final fetched = <String>[];
      fetchScript = (url) {
        fetched.add(url);
        return DescriptorFetched(
          LibraryDescriptor(
            fingerprint: fpB,
            name: 'Fetched Library',
            siteUrl: 'https://a.github.io/x/',
            updatedAt: 1,
          ),
        );
      };
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
      await tester.pumpAndSettle();

      expect(fetched, ['https://a.github.io/x/library.json']);
      expect(find.text('Fetched Library'), findsOneWidget);
      expect(find.textContaining('Last refreshed'), findsOneWidget);
      expect(find.textContaining('1 up to date'), findsOneWidget);
      expect(repo.applyCalls, hasLength(1));
    });

    testWidgets('an unreachable site keeps the cached row and says so', (
      tester,
    ) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: 'https://a.github.io/x/',
          name: 'Cached Name',
          location: GeoPoint.tryCreate(12.5, 77.5),
          precision: LocationPrecision.exact,
          fetchStatus: FetchStatus.ok,
          fetchedAt: 500,
        ),
      ];
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('Cached Name'), findsOneWidget); // offline keeps data
      expect(find.textContaining('1 unreachable'), findsOneWidget);
    });
  });

  group('distance sorting (§7 S4)', () {
    testWidgets('with an own pin, pinned rows sort nearest-first', (
      tester,
    ) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: 'https://far.github.io/x/',
          name: 'Far Away',
          location: GeoPoint.tryCreate(13.9, 78.9),
          precision: LocationPrecision.exact,
        ),
        const NetworkLibrary(
          id: 2,
          siteUrl: 'https://nopin.github.io/x/',
          name: 'No Pin',
        ),
        NetworkLibrary(
          id: 3,
          siteUrl: 'https://near.github.io/x/',
          name: 'Very Near',
          location: GeoPoint.tryCreate(12.95, 77.65),
          precision: LocationPrecision.exact,
        ),
      ];
      // Own pin = settings GPS × sharing (D7). The sharing key is absent and
      // the GPS non-blank ⇒ the first-read rule yields `exact`.
      await pumpPage(
        tester,
        prefs: const {'publish_contact_gps': '12.9, 77.6'},
      );

      final nearY = tester.getTopLeft(find.text('Very Near')).dy;
      final farY = tester.getTopLeft(find.text('Far Away')).dy;
      final noPinY = tester.getTopLeft(find.text('No Pin')).dy;
      expect(nearY, lessThan(farY));
      expect(farY, lessThan(noPinY)); // pin-less rows follow, by name
    });

    testWidgets('without an own pin, rows sort by name', (tester) async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://z.github.io/x/',
          name: 'Zebra',
        ),
        const NetworkLibrary(
          id: 2,
          siteUrl: 'https://a.github.io/x/',
          name: 'Apple',
        ),
      ];
      await pumpPage(tester); // no GPS in prefs ⇒ sharing off ⇒ no own pin
      final appleY = tester.getTopLeft(find.text('Apple')).dy;
      final zebraY = tester.getTopLeft(find.text('Zebra')).dy;
      expect(appleY, lessThan(zebraY));
    });
  });

  testWidgets('My card tab: unpublished explains what to do first', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text('My card'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('appears once you have published'),
      findsOneWidget,
    );
    expect(find.byType(QrView), findsNothing);
  });

  testWidgets('My card tab: published shows the card QR and its payload', (
    tester,
  ) async {
    await pumpPage(tester, publishedUrl: 'https://me.github.io/lib/');
    await tester.tap(find.text('My card'));
    await tester.pumpAndSettle();

    final qr = tester.widget<QrView>(find.byType(QrView));
    final card = LibraryCardPayload.parse(qr.data);
    expect(card, isNotNull);
    expect(card!.siteUrl, 'https://me.github.io/lib/');
    expect(card.fingerprint, isNot(rawId)); // D3, again at the UI edge
    expect(qr.data, isNot(contains(rawId)));
    expect(find.text('https://me.github.io/lib/'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Share as image'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    repo.rows = [
      const NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'Member Library',
        source: NetworkSource.card,
        isMember: true,
      ),
      const NetworkLibrary(
        id: 2,
        siteUrl: 'https://hub.github.io/h/',
        name: 'Pending Hub',
        membership: MembershipState.pending,
      ),
    ];
    await pumpPage(tester);
    await expectMeetsA11yGuidelines(tester);
  });

  group('L6: the tile list builds lazily', () {
    testWidgets('a 200-row list builds a bounded number of tiles and still '
        'scrolls to the end', (tester) async {
      repo.rows = [
        for (var i = 0; i < 200; i++)
          NetworkLibrary(
            id: i + 1,
            siteUrl: 'https://lib$i.github.io/',
            name: 'Row $i',
            sortOrder: i,
          ),
      ];
      await pumpPage(tester);

      // The whole point of the sliver list: only the on-screen tiles exist.
      expect(
        tester.widgetList(find.byType(NetworkLibraryTile)).length,
        lessThan(40),
        reason: 'an eager list would build all 200 tiles at once',
      );
      await expectMeetsA11yGuidelines(tester); // populated-list a11y gate

      final listScrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Row 199'),
        400,
        scrollable: listScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('Row 199'), findsOneWidget);
    });
  });
}

/// In-memory repository fake; mutations really mutate so every invalidation
/// path re-reads a changed list (the page never patches from memory).
class _FakeRepo implements NetworkRepository {
  _FakeRepo(this.rows);

  List<NetworkLibrary> rows;
  final List<NetworkLibrary> upserts = [];
  final List<(List<NetworkLibrary>, List<NetworkLibrary>)> applyCalls = [];

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    upserts.add(row);
    final index = rows.indexWhere((r) => r.siteUrl == row.siteUrl);
    if (index >= 0) {
      rows[index] = row.copyWith(id: rows[index].id);
      return right(rows[index]);
    }
    final saved = row.copyWith(id: rows.length + 1);
    rows.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, Unit>> removeById(int id) async {
    rows.removeWhere((r) => r.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, RefreshApplyResult>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered, {
    // The page tests never edit a row mid-refresh, so the M1 baseline guard
    // is accepted but not simulated (repository + use-case tests cover it).
    List<NetworkLibrary> baselines = const [],
  }) async {
    applyCalls.add((List.of(updated), List.of(discovered)));
    for (final update in updated) {
      final index = rows.indexWhere((r) => r.id == update.id);
      if (index >= 0) rows[index] = update;
    }
    var nextId = rows.fold(0, (max, r) => r.id > max ? r.id : max);
    for (final insert in discovered) {
      nextId++;
      rows.add(insert.copyWith(id: nextId));
    }
    return right(
      RefreshApplyResult(applied: updated.length, inserted: discovered.length),
    );
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
