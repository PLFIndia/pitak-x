@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

// Transitive dependency of file_selector; imported only for the picker seam
// (same pattern as restore_page_test.dart). Deliberately NOT added to
// pubspec so the dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

import '../features/backup/generation_fixture.dart';
import '../features/library/replacement_test_guard.dart';
import '../features/periodicals/application/periodical_fakes.dart';
import '../features/publish/support/cloudflare_fakes.dart';
import '../features/vault/vault_repository_write_stub.dart';
import 'golden_names.dart';

/// Golden tests for the five screens users see most.
///
/// Plain `matchesGoldenFile`, no package (golden_toolkit is discontinued).
/// The default test font (Ahem) keeps rendering deterministic. **Linux CI is
/// the reference renderer** (dart_test.yaml explains why macOS local runs
/// should use `--exclude-tags golden`); regenerate via the `update-goldens`
/// workflow_dispatch job and commit the uploaded PNGs.
///
/// Every golden renders with the PRODUCTION theme (`AppTheme`, the same
/// object `main.dart` passes to `MaterialApp`) on a phone-sized viewport —
/// otherwise the PNGs would pin a default-blue 800×600 desktop window that
/// no user ever sees, and a theme regression would never show up here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const books = [
    CatalogueItem(id: 1, title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
    CatalogueItem(id: 2, title: 'Dune', author: 'Herbert'),
    // ADR 0013 U1: the row badges — an issue ("Issue") and an other item
    // ("Other"). A plain book carries no badge, so without these rows the
    // library goldens would never pin the badge rendering S14 added.
    CatalogueItem(
      id: 3,
      title: 'Frontline — Vol 42 No 12 (Sep 2026)',
      publisher: 'Kasturi & Sons',
      details: IssueOf(
        periodicalUid: 'uid-frontline',
        volume: 42,
        issueNumber: 12,
      ),
    ),
    CatalogueItem(id: 4, title: 'Catan', details: OtherItemOf()),
  ];

  /// Phone profile (≈ Pixel-class, 412×915 dp at 2.625×). Android is the
  /// only shipping target, so this — not the 800×600 test default — is the
  /// layout a truncation regression would appear on.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  /// Wraps [home] exactly as `main.dart` does for theming: light/dark from
  /// [AppTheme], selected by [dark].
  Widget themedApp(Widget home, {bool dark = false}) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  );

  Widget libraryApp(List<CatalogueItem> list, {bool dark = false}) =>
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _GoldenBookRepo(list),
          ),
          // S14: the rows watch the series-cover map (W4) — empty store, and
          // pin nowTick (PeriodicalsController arms the real 60 s timer).
          periodicalRepositoryProvider.overrideWith(
            (ref) async => _NoPeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: themedApp(const LibraryPage(), dark: dark),
      );

  const publishedSite = 'https://kadugodi.github.io/pitak/';
  const publishedSeriesUid = 'series-chandamama';

  /// One fixed book, grouped issue and Other row. Every value that could
  /// otherwise depend on a clock, locale, HTTP response or isolate is pinned.
  PublishedCatalogue goldenPublishedCatalogue() => PublishedCatalogue(
    declaredSchemaVersion: 1,
    exportedAt: 1760000000000,
    periodicals: const [
      PublishedPeriodical(
        periodicalUid: publishedSeriesUid,
        title: 'Chandamama',
        publisher: 'Chandamama India',
        language: 'Telugu',
      ),
    ],
    items: const [
      PublishedCatalogueItem(
        sourceIndex: 0,
        title: 'The Water Margin',
        kind: PublishedItemKind.book,
        author: "Shi Nai'an",
        language: 'English',
        ageGroup: AgeGroup.above10,
        coverUrl: 'covers/golden-book.jpg',
      ),
      PublishedCatalogueItem(
        sourceIndex: 1,
        title: 'Chandamama — Vol 249 No 10',
        kind: PublishedItemKind.magazineIssue,
        language: 'Telugu',
        issue: PublishedIssueDetails(
          periodicalUid: publishedSeriesUid,
          volume: 249,
          issueNumber: 10,
        ),
      ),
      PublishedCatalogueItem(
        sourceIndex: 2,
        title: 'Kannada Picture Dictionary',
        kind: PublishedItemKind.other,
        language: 'Kannada',
        ageGroup: AgeGroup.above6,
      ),
    ],
  );

  /// Real, tiny JPEG bytes: the golden exercises the production memory-image
  /// path without a network URL or a platform image picker.
  Uint8List goldenCoverBytes() => Uint8List.fromList(
    img.encodeJpg(
      img.Image(width: 4, height: 6)..clear(img.ColorRgb8(32, 96, 160)),
    ),
  );

  Widget publishedCatalogueApp({required bool dark}) {
    final catalogue = goldenPublishedCatalogue();
    final coverBytes = goldenCoverBytes();
    return ProviderScope(
      overrides: [
        publishedCatalogueFetcherProvider(
          publishedSite,
        ).overrideWithValue((url, {abortTrigger}) async => right(catalogue)),
        // The production query engine, synchronously. Its isolate adapter is
        // tested separately and must not introduce timing into this image.
        publishedCatalogueQueryRunnerProvider.overrideWithValue(
          (catalogue, query) async =>
              PublishedQueryEngine.apply(catalogue, query),
        ),
        publishedEventsFetcherProvider(
          publishedSite,
        ).overrideWithValue((url, {abortTrigger}) async => const Right(null)),
        publishedCoverFetcherProvider(publishedSite).overrideWithValue(
          (request, {abortTrigger}) async => Uint8List.fromList(coverBytes),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) async => const _GoldenPublishedSettings(),
        ),
      ],
      child: themedApp(
        PublishedCataloguePage(
          row: const NetworkLibrary(
            siteUrl: publishedSite,
            name: 'Kadugodi Library',
          ),
          opener: PublishedSiteOpener(
            launch: (url, mode) =>
                throw StateError('Golden tests must not launch a browser'),
          ),
        ),
        dark: dark,
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester,
    Widget widget,
    String name,
  ) async {
    // Sync guard (review H1.2): every rendered golden must be listed in
    // kGoldenNames, or the non-tagged existence guard cannot cover its PNG.
    // The other direction (a listed name with no PNG) is caught by
    // golden_files_exist_test.dart in the normal suite.
    expect(
      kGoldenNames,
      contains(name),
      reason: 'add "$name" to kGoldenNames in test/golden/golden_names.dart',
    );
    usePhoneViewport(tester);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('library page, populated, light', (tester) async {
    await expectGolden(tester, libraryApp(books), 'library_populated_light');
  });

  testWidgets('library page, populated, dark', (tester) async {
    await expectGolden(
      tester,
      libraryApp(books, dark: true),
      'library_populated_dark',
    );
  });

  testWidgets('library page, empty, light', (tester) async {
    await expectGolden(tester, libraryApp(const []), 'library_empty_light');
  });

  testWidgets('published catalogue, populated, light', (tester) async {
    await expectGolden(
      tester,
      publishedCatalogueApp(dark: false),
      'published_catalogue_populated_light',
    );
  });

  testWidgets('published catalogue, populated, dark', (tester) async {
    await expectGolden(
      tester,
      publishedCatalogueApp(dark: true),
      'published_catalogue_populated_dark',
    );
  });

  group('vault unlock', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('golden_vault'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('vault unlock form', (tester) async {
      final store = VaultStore(baseDir: tmp.path);
      File(store.dbPath).writeAsBytesSync([0]);
      store.writeBlob('salt.iv.ct');
      final container = ProviderContainer(
        overrides: [
          vaultRepositoryProvider.overrideWithValue(_GoldenVault()),
          vaultStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);
      await expectGolden(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: themedApp(const VaultPage()),
        ),
        'vault_unlock',
      );
    });
  });

  testWidgets('publish connection tab', (tester) async {
    final cloudflare = CloudflareSetupHarness();
    await expectGolden(
      tester,
      ProviderScope(
        overrides: [
          publishCredentialStoreProvider.overrideWithValue(_GoldenCreds()),
          setupCloudflareSiteProvider.overrideWith(
            (ref) async => cloudflare.setup,
          ),
          cloudflareCredentialStoreProvider.overrideWithValue(
            cloudflare.credentials,
          ),
          // Pin the signed-out host projection as well. Without this, the
          // publish card reads platform storage and its loading spinner makes
          // pumpAndSettle time out before a screenshot can be taken.
          publishSiteStatusProvider.overrideWith(
            (ref) async => const PublishSiteStatus(
              activeHost: null,
              target: null,
              verifiedSiteUrl: null,
              setupMessage: 'Pick a target repo first.',
            ),
          ),
        ],
        child: themedApp(const PublishPage()),
      ),
      'publish_connection',
    );
  });

  /// The network list tile in every badge state (docs/ARCHITECTURE.md §3 network): member
  /// + verified, unverified, the pending-membership prompt, declined with
  /// Reconsider, and an identity conflict. One column, one PNG — the badges
  /// and their exact words are what a regression would break.
  group('network library tile', () {
    testWidgets('badge states', (tester) async {
      void noop() {}
      await expectGolden(
        tester,
        themedApp(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const NetworkLibraryTile(
                    row: NetworkLibrary(
                      id: 1,
                      siteUrl: 'https://meera.github.io/books/',
                      name: 'Meera Road Library',
                      source: NetworkSource.card,
                      isMember: true,
                      memberVerified: true,
                    ),
                  ),
                  const NetworkLibraryTile(
                    row: NetworkLibrary(
                      id: 2,
                      siteUrl: 'https://banyan.github.io/club/',
                      name: 'Banyan Reading Club',
                      source: NetworkSource.card,
                      isMember: true,
                    ),
                  ),
                  NetworkLibraryTile(
                    row: const NetworkLibrary(
                      id: 3,
                      siteUrl: 'https://hub.github.io/net/',
                      name: 'District Hub',
                      membership: MembershipState.pending,
                    ),
                    onConfirmMembership: noop,
                    onDeclineMembership: noop,
                  ),
                  NetworkLibraryTile(
                    row: const NetworkLibrary(
                      id: 4,
                      siteUrl: 'https://old.github.io/net/',
                      name: 'Old Hub',
                      membership: MembershipState.declined,
                    ),
                    onReconsiderMembership: noop,
                  ),
                  const NetworkLibraryTile(
                    row: NetworkLibrary(
                      id: 5,
                      siteUrl: 'https://clash.github.io/x/',
                      name: 'Clashing Library',
                      fetchStatus: FetchStatus.identityConflict,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        'network_library_tiles',
      );
    });
  });

  /// The Magazines list in every badge state (ADR 0013 D5): subscribed,
  /// expiring soon, lapsed, untracked (no badge) and a removed title, plus
  /// the "N issues · latest YYYY-MM" summary and a publisher line. The
  /// badges and their exact words are what a regression would break. (S17
  /// deferred this golden so that test, name and Linux PNG land together.)
  group('magazine title rows', () {
    testWidgets('badge states', (tester) async {
      // Fixed "now" for the derived statuses (D5): subscribed = +60 days,
      // expiring soon = +10 days, lapsed = −1 day — the periodicals page
      // test's numbers, so the two suites agree on what each badge means.
      final t0 = DateTime(2026, 10, 23, 12).millisecondsSinceEpoch;
      final today = CalendarDate.fromPickerDate(DateTime(2026, 10, 23, 12));
      int dayFromToday(int offset) => today.addDays(offset).epochMillis;
      final periodicals = FakePeriodicals()
        ..seed(
          const Periodical(title: 'Chandamama', publisher: 'Chandamama India'),
        ) // untracked: no badge, publisher line
        ..seed(Periodical(title: 'Outlook', subscriptionEnd: dayFromToday(10)))
        ..seed(
          Periodical(title: 'Sportstar', subscriptionEnd: dayFromToday(-1)),
        )
        ..seed(const Periodical(title: 'Old Weekly', removed: true));
      final frontline = periodicals.seed(
        Periodical(title: 'Frontline', subscriptionEnd: dayFromToday(60)),
      );
      // Two issues for Frontline, the newest dated 2026-09 → the summary
      // line reads "2 issues · latest 2026-09".
      final uid = frontline.periodicalUid!;
      periodicals.issues[uid] = [
        CatalogueItem(
          id: 1,
          title: 'Frontline — No 1',
          details: IssueOf(
            periodicalUid: uid,
            issueDate: DateTime.utc(2026, 8).millisecondsSinceEpoch,
          ),
        ),
        CatalogueItem(
          id: 2,
          title: 'Frontline — No 2',
          details: IssueOf(
            periodicalUid: uid,
            issueDate: DateTime.utc(2026, 9).millisecondsSinceEpoch,
          ),
        ),
      ];
      await expectGolden(
        tester,
        ProviderScope(
          overrides: [
            periodicalRepositoryProvider.overrideWith(
              (ref) async => periodicals,
            ),
            catalogueItemRepositoryProvider.overrideWith(
              (ref) async => FakeItems(),
            ),
            settingsRepositoryProvider.overrideWith(
              (ref) async => FakeSettings(),
            ),
            clockProvider.overrideWithValue(() => t0),
            // The controller's build arms the real 60 s timer — pin it so
            // pumpAndSettle can settle (the S14 override pair).
            nowTickProvider.overrideWith((ref) => 0),
          ],
          child: themedApp(const PeriodicalsPage()),
        ),
        'periodicals_badge_states',
      );
    });
  });

  group('restore page', () {
    late Directory tmp;
    late GenerationFixture gen;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('golden_restore');
      gen = GenerationFixture(tmp);
    });
    tearDown(() async {
      await gen.db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('restore page, initial', (tester) async {
      FileSelectorPlatform.instance = _GoldenFileSelector();
      await expectGolden(
        tester,
        ProviderScope(
          overrides: [
            restoreBackupProvider.overrideWith(
              (ref) async => gen.restorer(
                vault: _GoldenVault(),
                guard: FakeReplacementGuard(),
              ),
            ),
            vaultStoreProvider.overrideWith((ref) async => gen.store),
          ],
          child: themedApp(const RestorePage()),
        ),
        'restore_initial',
      );
    });
  });
}

/// Explicit cover consent for the viewer golden; no SharedPreferences plugin.
class _GoldenPublishedSettings implements SettingsRepository {
  const _GoldenPublishedSettings();

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(loadRemoteCovers: true);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call in viewer golden');
}

/// In-memory series store: no series — the row cover-fallback map (S14) only
/// needs `listAll` to answer.
class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

/// In-memory book repo returning a fixed list (enough for a rendered frame).
class _GoldenBookRepo implements CatalogueItemRepository {
  _GoldenBookRepo(this._all);
  final List<CatalogueItem> _all;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(_all);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final end = (offset + limit).clamp(0, _all.length);
    final start = offset.clamp(0, end);
    return right(
      CatalogueItemPage(
        items: _all.sublist(start, end),
        hasMore: end < _all.length,
      ),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      right(_all.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
      right(books.length);
}

/// Vault fake: unlock succeeds with an empty vault (not exercised visually).
class _GoldenVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

/// Publish credential store with nothing stored (signed-out state).
class _GoldenCreds implements PublishCredentialStore {
  @override
  Future<String?> token() async => null;
  @override
  Future<String?> targetRepo() async => null;
  @override
  Future<void> clearToken() async {}
  @override
  Future<void> setTargetRepo(String target) async {}
  @override
  Future<void> clearTargetRepo() async {}
  @override
  Future<void> setToken(String token) async {}
}

/// Picker seam so the restore page never touches real file IO.
class _GoldenFileSelector extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => null;
}
