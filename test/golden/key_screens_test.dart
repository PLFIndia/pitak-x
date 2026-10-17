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
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

import '../features/backup/generation_fixture.dart';
import '../features/library/replacement_test_guard.dart';
import '../features/vault/vault_repository_write_stub.dart';

/// Golden tests for the five screens users see most (architecture.md B2).
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
    Book(id: 1, title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
    Book(id: 2, title: 'Dune', author: 'Herbert'),
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

  Widget libraryApp(List<Book> list, {bool dark = false}) => ProviderScope(
    overrides: [
      bookRepositoryProvider.overrideWith((ref) async => _GoldenBookRepo(list)),
    ],
    child: themedApp(const LibraryPage(), dark: dark),
  );

  Future<void> expectGolden(
    WidgetTester tester,
    Widget widget,
    String name,
  ) async {
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

  /// The network list tile in every badge state (libNetwork.md §7 S5): member
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

/// In-memory book repo returning a fixed list (enough for a rendered frame).
class _GoldenBookRepo implements BookRepository {
  _GoldenBookRepo(this._all);
  final List<Book> _all;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_all);
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final end = (offset + limit).clamp(0, _all.length);
    final start = offset.clamp(0, end);
    return right(
      BookPage(items: _all.sublist(start, end), hasMore: end < _all.length),
    );
  }

  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(_all.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    BookSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book book) async => right(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async =>
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
