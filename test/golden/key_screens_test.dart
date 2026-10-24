@Tags(['golden'])
library;

import 'dart:io';

// Transitive dependency of file_selector; imported only for the picker seam
// (same pattern as restore_page_test.dart). Deliberately NOT added to
// pubspec so the dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

import '../features/backup/generation_fixture.dart';
import '../features/library/replacement_test_guard.dart';
import '../features/periodicals/application/periodical_fakes.dart';
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
    await expectGolden(
      tester,
      ProviderScope(
        overrides: [
          publishCredentialStoreProvider.overrideWithValue(_GoldenCreds()),
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
      const day = 24 * 60 * 60 * 1000;
      final periodicals = FakePeriodicals()
        ..seed(
          const Periodical(title: 'Chandamama', publisher: 'Chandamama India'),
        ) // untracked: no badge, publisher line
        ..seed(Periodical(title: 'Outlook', subscriptionEnd: t0 + 10 * day))
        ..seed(Periodical(title: 'Sportstar', subscriptionEnd: t0 - day))
        ..seed(const Periodical(title: 'Old Weekly', removed: true));
      final frontline = periodicals.seed(
        Periodical(title: 'Frontline', subscriptionEnd: t0 + 60 * day),
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
            issueDate: DateTime(2026, 8).millisecondsSinceEpoch,
          ),
        ),
        CatalogueItem(
          id: 2,
          title: 'Frontline — No 2',
          details: IssueOf(
            periodicalUid: uid,
            issueDate: DateTime(2026, 9).millisecondsSinceEpoch,
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
