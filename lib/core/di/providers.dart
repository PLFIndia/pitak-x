/// Dependency-injection providers (AGENTS.md §4: Riverpod codegen is the DI
/// container — no GetIt, no service locators).
///
/// The non-secret Drift database and the repositories/use cases over it are
/// wired here. The encrypted vault is reached through the Rust FFI core via
/// [vaultRepository]; the vault key never enters Dart.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/platform/screen_security.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/infrastructure/prefs_bookmarks_repository.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/events/infrastructure/file_events_repository.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart'
    hide PdfTextRasterizer, RasterizedText;
import 'package:pitaka/features/library/application/add_book_use_case.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/application/update_book_use_case.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/lookup/application/chained_isbn_lookup.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/in_memory_isbn_cache.dart';
import 'package:pitaka/features/lookup/infrastructure/open_library_lookup_service.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishedFileFetcher, RemoteCoverFetcher;
import 'package:pitaka/features/publish/application/setup_github_repo.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_html_ports.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_cover_fetcher.dart';
import 'package:pitaka/features/publish/infrastructure/events_html_builder.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_manifest_store.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_publish_credential_store.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:pitaka/features/vault/application/open_vault_from_archive.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/pending_snapshot.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/ffi_vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/local_auth_biometric_authenticator.dart';
import 'package:pitaka/features/vault/infrastructure/secure_storage_biometric_keystore.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

part 'providers.g.dart';

/// The app's document directory (where the DB + covers live). Resolved once.
@Riverpod(keepAlive: true)
Future<Directory> appDocsDir(AppDocsDirRef ref) =>
    getApplicationDocumentsDirectory();

/// The non-secret Drift database (books + wishlist).
///
/// `keepAlive`: the open DB must survive navigation; reopening per-screen would
/// thrash the connection. Closed when the provider is finally disposed.
@Riverpod(keepAlive: true)
Future<AppDatabase> appDatabase(AppDatabaseRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  final file = File(p.join(dir.path, 'pitaka.db'));
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  ref.onDispose(db.close);
  return db;
}

/// Absolute path to the covers directory (`<appDocs>/covers`), where local
/// book covers are stored. Resolved once; used by cover-rendering widgets.
@riverpod
Future<String> coversDir(CoversDirRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return p.join(dir.path, 'covers');
}

/// The app's shared (non-secret) key-value preferences store.
@Riverpod(keepAlive: true)
Future<SharedPreferences> sharedPreferences(SharedPreferencesRef ref) =>
    SharedPreferences.getInstance();

/// Non-secret settings persistence (theme, library identity, sort).
@riverpod
Future<SettingsRepository> settingsRepository(SettingsRepositoryRef ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsSettingsRepository(prefs);
}

/// Library-bookmarks persistence (other libraries' published sites). Non-secret
/// flat list in shared_preferences — no Drift table/migration.
@riverpod
Future<BookmarksRepository> bookmarksRepository(
  BookmarksRepositoryRef ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsBookmarksRepository(prefs);
}

/// Library books repository.
@riverpod
Future<BookRepository> bookRepository(BookRepositoryRef ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftBookRepository(db);
}

/// Local cover-file store (`<docs>/covers/<uuid>.jpg`) for captured covers.
@riverpod
Future<CoverStore> coverStore(CoverStoreRef ref) async {
  final dir = await ref.watch(coversDirProvider.future);
  return CoverStore(coversDir: dir);
}

/// Distinct non-blank languages present in the library (filter-chip facets).
@riverpod
Future<List<String>> libraryLanguages(LibraryLanguagesRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final result = await repo.distinctLanguages();
  return result.getOrElse((_) => const []);
}

/// Adds a new book to the library (title-required validation + persist).
@riverpod
Future<AddBookUseCase> addBookUseCase(AddBookUseCaseRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  return AddBookUseCase(repo);
}

/// Updates an existing library book (title-required, id-immutable).
@riverpod
Future<UpdateBookUseCase> updateBookUseCase(UpdateBookUseCaseRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  return UpdateBookUseCase(repo);
}

/// Hard-deletes a library book, purging its vault loans when unlocked (#27/D3).
/// The vault side is the session controller (it satisfies [VaultLoanPurger]).
@riverpod
Future<DeleteBookUseCase> deleteBookUseCase(DeleteBookUseCaseRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final vault = ref.read(vaultSessionControllerProvider.notifier);
  return DeleteBookUseCase(books: repo, vault: vault);
}

/// Wishlist repository.
@riverpod
Future<WishlistRepository> wishlistRepository(WishlistRepositoryRef ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftWishlistRepository(db);
}

/// Adds a new wishlist entry (title-required validation + persist).
@riverpod
Future<AddWishlistBookUseCase> addWishlistBookUseCase(
  AddWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return AddWishlistBookUseCase(repo);
}

/// Updates a wishlist entry (title-required; id + addedDate immutable).
@riverpod
Future<UpdateWishlistBookUseCase> updateWishlistBookUseCase(
  UpdateWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return UpdateWishlistBookUseCase(repo);
}

/// Deletes a wishlist entry by id.
@riverpod
Future<DeleteWishlistBookUseCase> deleteWishlistBookUseCase(
  DeleteWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return DeleteWishlistBookUseCase(repo);
}

/// Marks a wishlist entry purchased, with optional move-to-library (D2 check).
@riverpod
Future<MarkWishlistPurchasedUseCase> markWishlistPurchasedUseCase(
  MarkWishlistPurchasedUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  final books = await ref.watch(bookRepositoryProvider.future);
  return MarkWishlistPurchasedUseCase(repo, books: books);
}

/// Encrypted borrowers vault, read through the Rust FFI core.
@riverpod
VaultRepository vaultRepository(VaultRepositoryRef ref) =>
    const FfiVaultRepository();

/// Shared HTTP client (#30, closes audit m1). Timeout-bounded so a dead
/// socket (OEM app freezers, dropped mobile data) fails closed instead of
/// hanging callers forever. Closed when disposed.
@Riverpod(keepAlive: true)
http.Client httpClient(HttpClientRef ref) {
  final client = TimeoutHttpClient(http.Client());
  ref.onDispose(client.close);
  return client;
}

/// Session-scoped ISBN lookup cache (#30). Non-secret public metadata.
@Riverpod(keepAlive: true)
IsbnCache isbnCache(IsbnCacheRef ref) => InMemoryIsbnCache();

/// ISBN lookup + title search (#29/#30): Open Library primary, Google Books
/// fallback, chained over the cache. Only hit on explicit user action.
@riverpod
IsbnLookupService isbnLookupService(IsbnLookupServiceRef ref) {
  final client = ref.watch(httpClientProvider);
  return ChainedIsbnLookup(
    primary: OpenLibraryLookupService(client: client),
    fallback: GoogleBooksLookupService(client: client),
    cache: ref.watch(isbnCacheProvider),
  );
}

// --- Publish to GitHub Pages (#32) ---------------------------------------

/// GitHub API client for publishing (device flow + git data). Shares the app
/// HTTP client.
@riverpod
GitHubApi gitHubApi(GitHubApiRef ref) =>
    HttpGitHubApi(client: ref.watch(httpClientProvider));

/// Encrypted-at-rest GitHub publish credentials (token + clientId + repo).
@Riverpod(keepAlive: true)
PublishCredentialStore publishCredentialStore(PublishCredentialStoreRef ref) =>
    SecureStoragePublishCredentialStore();

/// GitHub Device Flow runner (#32 auth).
@riverpod
GitHubDeviceFlow gitHubDeviceFlow(GitHubDeviceFlowRef ref) =>
    GitHubDeviceFlow(ref.watch(gitHubApiProvider));

/// One-tap repo setup: create/adopt the publish repo + enable Pages
/// (mirrors Localcart Orange's github_setup).
@riverpod
SetupGitHubRepo setupGitHubRepo(SetupGitHubRepoRef ref) => SetupGitHubRepo(
  ref.watch(gitHubApiProvider),
  ref.watch(publishCredentialStoreProvider),
);

/// Bounded remote-cover fetch port (M1: allow-list + timeout + byte cap),
/// with the publish downscale applied. Injected into the publish controller
/// as a domain function type so the application layer never constructs the
/// HTTP-backed fetcher itself (§3.1).
@riverpod
RemoteCoverFetcher remoteCoverFetcher(RemoteCoverFetcherRef ref) {
  final client = ref.watch(httpClientProvider);
  return (url) async {
    final raw = await BoundedCoverFetcher(client: client).fetch(url);
    if (raw == null) return null;
    // Downscale before publishing (400x600 q80) so the git push stays small.
    return ImageDownscaler.downscaleJpeg(raw) ?? raw;
  };
}

/// Published-file fetcher for the post-publish read-back (à la Localcart
/// Orange): plain GET of a PUBLIC Pages URL — no auth, no token. Null on any
/// failure; the read-back treats that as "not visible yet".
@riverpod
PublishedFileFetcher publishedFileFetcher(PublishedFileFetcherRef ref) {
  final client = ref.watch(httpClientProvider);
  return (url) async {
    try {
      final resp = await client.get(Uri.parse(url));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    } on Exception {
      return null;
    }
  };
}

/// Viewer-HTML factory port: loads the bundled template (rootBundle — a side
/// effect, so it lives behind this seam) and substitutes the library values.
@riverpod
ViewerHtmlFactory viewerHtmlFactory(ViewerHtmlFactoryRef ref) =>
    ({required libraryName, required contact}) =>
        ViewerHtmlBuilder(libraryName: libraryName, contact: contact).build();

/// Events-HTML factory port: same seam as [viewerHtmlFactory] for the events
/// page template.
@riverpod
EventsHtmlFactory eventsHtmlFactory(EventsHtmlFactoryRef ref) =>
    ({required libraryName, required posters}) =>
        EventsHtmlBuilder(libraryName: libraryName, posters: posters).build();

/// Salted cover-path ids for publish (no internal-id leak, F-01).
@riverpod
PublishCoverIds publishCoverIds(PublishCoverIdsRef ref) =>
    PublishCoverIds(SecureStorageCoverSaltStore());

/// File-backed incremental-publish manifest, rooted at the app docs dir.
@riverpod
Future<FilePublishManifestStore> publishManifestStore(
  PublishManifestStoreRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return FilePublishManifestStore(baseDir: dir.path);
}

/// The live URL of the user's published library site, or null when nothing
/// has been published yet. Derived from the publish manifest's `repo` field,
/// which is only written AFTER a successful publish — so this is null for a
/// repo that was created but never published. Public data (the URL is the
/// whole point); no secrets involved.
@riverpod
Future<String?> publishedSiteUrl(PublishedSiteUrlRef ref) async {
  final store = await ref.watch(publishManifestStoreProvider.future);
  return githubPagesUrlFor(store.load().repo);
}

/// OS-level screen-capture protection toggle (Android FLAG_SECURE) for vault
/// PII screens (#34/F-12). A narrow platform channel; no-op off Android.
@riverpod
ScreenSecurity screenSecurity(ScreenSecurityRef ref) =>
    const MethodChannelScreenSecurity();

/// Hands generated files (exports, backups) to the OS share sheet. Overridden
/// in widget tests with a fake to assert what would be shared.
@riverpod
FileShareService fileShareService(FileShareServiceRef ref) =>
    const SharePlusFileShareService();

/// Biometric/device-credential gate for optional vault unlock (#34 B2). Only
/// gates release of the hardware-stored secret S; never sees the vault key.
@riverpod
BiometricAuthenticator biometricAuthenticator(BiometricAuthenticatorRef ref) =>
    LocalAuthBiometricAuthenticator();

/// Hardware-backed store (Keystore/Keychain) for the biometric secret S (#34
/// B2). S is the only thing persisted for biometric unlock; the passphrase is
/// never stored.
@riverpod
BiometricKeyStore biometricKeyStore(BiometricKeyStoreRef ref) =>
    SecureStorageBiometricKeyStore();

/// At-rest store for the persistent on-device vault (DB path + wrapped-key
/// blob), rooted at the app documents dir (#26.2, Q-26b).
@riverpod
Future<VaultStore> vaultStore(VaultStoreRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return VaultStore(baseDir: dir.path);
}

/// Active-loan counts per book id when the vault is UNLOCKED, or null when
/// locked/uninitialized (availability is unknown without the decrypted loans).
/// The library list watches this to show the "Not available" badge (#26.4).
@riverpod
Map<int, int>? activeLoanCounts(ActiveLoanCountsRef ref) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is VaultUnlocked) {
    return activeLoanCountsByBook(session.data.loans);
  }
  return null;
}

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return).
@riverpod
BorrowerProfile? borrowerProfile(BorrowerProfileRef ref, int borrowerId) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is! VaultUnlocked) return null;
  final borrower = session.data.borrowers
      .where((b) => b.id == borrowerId)
      .fold<Borrower?>(null, (_, b) => b);
  if (borrower == null) return null;
  return buildBorrowerProfile(
    borrower: borrower,
    allLoans: session.data.loans,
    now: DateTime.now().millisecondsSinceEpoch,
  );
}

/// The vault-gated pending/reminders snapshot (#27b): overdue + due-soon loans
/// (from the unlocked vault) and needs-metadata books (from the library), or
/// null when the vault is locked. Recomputes when either source changes.
@riverpod
Future<PendingSnapshot?> pendingSnapshot(PendingSnapshotRef ref) async {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  if (session is! VaultUnlocked) return null;
  final repo = await ref.watch(bookRepositoryProvider.future);
  final books = (await repo.getAll()).getOrElse((_) => const []);
  return buildPendingSnapshot(
    loans: session.data.loans,
    books: books,
    now: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Read-only opener that unlocks + reads a vault from a `.pitabak` archive
/// (writes nothing; stages the DB in a scratch dir under the app docs dir).
@riverpod
Future<OpenVaultFromArchive> openVaultFromArchive(
  OpenVaultFromArchiveRef ref,
) async {
  final vault = ref.watch(vaultRepositoryProvider);
  final dir = await ref.watch(appDocsDirProvider.future);
  return OpenVaultFromArchive(
    vault: vault,
    workDir: p.join(dir.path, 'vault_view_work'),
  );
}

/// Reads Pitaka bundle (.zip) archives into an import payload, writing any
/// bundled covers under `<appDocs>/covers`.
@riverpod
Future<LibraryBundleReader> libraryBundleReader(
  LibraryBundleReaderRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return LibraryBundleReader(coversDir: p.join(dir.path, 'covers'));
}

/// One-shot library/wishlist import use case.
@riverpod
Future<ImportLibraryUseCase> importLibraryUseCase(
  ImportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ImportLibraryUseCase(bookRepo: bookRepo, wishlistRepo: wishlistRepo);
}

/// One-shot library/wishlist export use case.
@riverpod
Future<ExportLibraryUseCase> exportLibraryUseCase(
  ExportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ExportLibraryUseCase(bookRepo: bookRepo, wishlistRepo: wishlistRepo);
}

/// Loads the bundled footer icon for the PDF export, or null when the asset
/// is missing (a missing icon must never block an export). Behind a provider
/// because `rootBundle` is a side effect the application layer must not own.
@riverpod
Future<Uint8List?> Function() pdfFooterIconLoader(PdfFooterIconLoaderRef ref) =>
    () async {
      try {
        final data = await rootBundle.load('assets/pdf/app_icon.png');
        return data.buffer.asUint8List();
      } on Object {
        return null;
      }
    };

/// Shaped-text rasterizer for the PDF export (needs a live Flutter engine +
/// the bundled Noto fonts — infrastructure, injected as the domain
/// `PdfTextRasterizer` port).
@riverpod
PdfTextRasterizer pdfTextRasterizer(PdfTextRasterizerRef ref) =>
    UiPdfTextRasterizer(
      regularAssets: pdfRegularFontAssets,
      boldAssets: pdfBoldFontAssets,
    );

/// Multi-maintainer library merge use case (PLAN-merge.md): reconciles an
/// incoming Pitaka-JSON file with the local catalogue behind the library-ID
/// gate. Reuses the book repo + settings (for the ID gate / adoption).
@riverpod
Future<MergeLibraryUseCase> mergeLibraryUseCase(
  MergeLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return MergeLibraryUseCase(bookRepo: bookRepo, settings: settings);
}

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled. Returns the archive bytes for the UI to save.
@riverpod
Future<CreateBackupUseCase> createBackupUseCase(
  CreateBackupUseCaseRef ref,
) async {
  final books = await ref.watch(bookRepositoryProvider.future);
  final wishlist = await ref.watch(wishlistRepositoryProvider.future);
  final store = await ref.watch(vaultStoreProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  final writer = BackupArchiveWriter(
    openDatabase: sqlite3.open,
    vaultStore: store,
    coversDir: p.join(dir.path, 'covers'),
  );
  return CreateBackupUseCase(
    books: books,
    wishlist: wishlist,
    writer: writer,
    workDir: p.join(dir.path, 'backup_create_work'),
  );
}

/// Backup-archive restorer (authoritative overwrite of local state).
@riverpod
Future<RestoreBackup> restoreBackup(RestoreBackupRef ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final vault = ref.watch(vaultRepositoryProvider);
  final store = await ref.watch(vaultStoreProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  return RestoreBackup(
    db: db,
    vault: vault,
    vaultStore: store,
    coversDir: p.join(dir.path, 'covers'),
    workDir: p.join(dir.path, 'restore_work'),
  );
}

/// Events (poster) persistence: `events.json` + `posters/<uuid>.jpg` under the
/// app docs dir. Poster images are downscaled (EXIF/GPS stripped) before save.
/// Poster bounds are larger + portrait-leaning vs the 2:3 book-cover default.
@riverpod
Future<EventsRepository> eventsRepository(EventsRepositoryRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return FileEventsRepository(
    baseDir: dir.path,
    downscale: (bytes) =>
        ImageDownscaler.downscaleJpeg(bytes, maxW: 1080, maxH: 1440),
  );
}
