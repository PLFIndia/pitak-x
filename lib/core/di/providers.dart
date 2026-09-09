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
import 'package:pitaka/core/network/lookup_http_client.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/platform/screen_security.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/infrastructure/prefs_bookmarks_repository.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/events/infrastructure/file_events_repository.dart';
import 'package:pitaka/features/events/infrastructure/poster_file_reader.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/logo_file_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart'
    hide PdfTextRasterizer, RasterizedText;
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/application/add_book_use_case.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/application/update_book_use_case.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/lookup/application/chained_isbn_lookup.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_key_store.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/in_memory_isbn_cache.dart';
import 'package:pitaka/features/lookup/infrastructure/open_library_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/secure_storage_lookup_key_store.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway, PublishedFileFetcher, RemoteCoverFetcher;
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
import 'package:pitaka/features/publish/infrastructure/local_cover_reader.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_publish_credential_store.dart';
import 'package:pitaka/features/publish/infrastructure/viewer_html_builder.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/pending_snapshot.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/ffi_vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/keystore_biometric_secret_vault.dart';
import 'package:pitaka/features/vault/infrastructure/local_auth_biometric_authenticator.dart';
import 'package:pitaka/features/vault/infrastructure/open_vault_from_archive.dart';
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

/// Versioned data-generation store under `<appDocs>/data` (M02). The
/// catalogue DB, covers and vault live INSIDE the active generation so a
/// restore can build a complete new set and switch to it atomically.
@Riverpod(keepAlive: true)
Future<DataGenerations> dataGenerations(DataGenerationsRef ref) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return DataGenerations(docsDir: dir.path);
}

/// The non-secret Drift database (books + wishlist), opened inside the active
/// data generation (M02) — switching generations closes and reopens it.
///
/// `keepAlive`: the open DB must survive navigation; reopening per-screen would
/// thrash the connection. Closed when the provider is finally disposed.
@Riverpod(keepAlive: true)
Future<AppDatabase> appDatabase(AppDatabaseRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  final file = File(generation.catalogueDbPath);
  final db = AppDatabase(NativeDatabase.createInBackground(file));
  ref.onDispose(db.close);
  return db;
}

/// Absolute path to the covers directory inside the active data generation
/// (M02), where local book covers are stored. Used by cover-rendering widgets.
@riverpod
Future<String> coversDir(CoversDirRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  return generation.coversDir;
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

/// Local cover-file store (`<docs>/covers/<uuid>.jpg`) for captured covers,
/// exposed as the domain [CoverFiles] port.
@riverpod
Future<CoverFiles> coverStore(CoverStoreRef ref) async {
  final dir = await ref.watch(coversDirProvider.future);
  return CoverStore(coversDir: dir);
}

/// Shared for the app lifetime: old/new auto-disposed callers must coordinate
/// on the same FIFO while an import or a cleanup operation is still running.
@Riverpod(keepAlive: true)
CoverFileCoordinator coverFileCoordinator(CoverFileCoordinatorRef ref) =>
    CoverFileCoordinator();

/// Removes cover files nothing references any more (decision Q12). Used right
/// after a cover/logo is replaced or a book hard-deleted, and once at startup
/// to sweep orphans left by older versions.
@riverpod
Future<CoverFileJanitor> coverFileJanitor(CoverFileJanitorRef ref) async {
  final books = await ref.watch(bookRepositoryProvider.future);
  // M11: wishlist rows reference covers in the same directory; the janitor
  // must count them as live references or startup sweeps delete their art.
  final wishlist = await ref.watch(wishlistRepositoryProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final store = await ref.watch(coverStoreProvider.future);
  return CoverFileJanitor(
    books: books,
    wishlist: wishlist,
    settings: settings,
    store: store,
    coordinator: ref.watch(coverFileCoordinatorProvider),
  );
}

/// One-shot startup sweep of orphan cover files; resolves to the number
/// removed. Triggered by the Library screen's first build (the composition
/// point that already owns the database), AFTER the list has loaded so the
/// sweep never competes with the first paint.
///
/// keepAlive: "once per app session" is the whole point — an autoDispose
/// provider would re-run the directory scan every time the screen rebuilt.
@Riverpod(keepAlive: true)
Future<int> orphanCoverSweep(OrphanCoverSweepRef ref) async {
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return janitor.sweep();
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
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return DeleteBookUseCase(
    books: repo,
    vault: vault,
    releaseCover: janitor.releaseReference,
  );
}

/// Lends a library book, enforcing the lending policy (removed / all copies
/// out → refused with a reason). The vault side is the session controller
/// (it satisfies [VaultLender]).
@riverpod
Future<LendBookUseCase> lendBookUseCase(LendBookUseCaseRef ref) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final vault = ref.read(vaultSessionControllerProvider.notifier);
  return LendBookUseCase(books: repo, vault: vault);
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

/// HTTP client for the public book-metadata APIs only. Differs from the
/// shared [httpClient] in two ways (REVIEW: lookup — "fails quite often"):
///  - 10 s timeout, not 60: lookups are interactive (user watching a
///    spinner); a slow provider should fail over to the fallback quickly,
///    not pin the button for a minute.
///  - [LookupHttpClient] on top: descriptive User-Agent (Open Library's API
///    policy throttles anonymous clients) + one jittered retry on 429/5xx.
@Riverpod(keepAlive: true)
http.Client lookupHttpClient(LookupHttpClientRef ref) {
  final client = LookupHttpClient(
    TimeoutHttpClient(http.Client(), timeout: const Duration(seconds: 10)),
  );
  ref.onDispose(client.close);
  return client;
}

/// Optional user-supplied Google Books API key (encrypted at rest, §6.3).
/// keepAlive: tiny, session-stable, and read on every lookup.
@Riverpod(keepAlive: true)
LookupKeyStore lookupKeyStore(LookupKeyStoreRef ref) =>
    SecureStorageLookupKeyStore();

/// ISBN lookup + title search (#29/#30): Open Library primary, Google Books
/// fallback, chained over the cache. Only hit on explicit user action.
@riverpod
IsbnLookupService isbnLookupService(IsbnLookupServiceRef ref) {
  final client = ref.watch(lookupHttpClientProvider);
  final keys = ref.watch(lookupKeyStoreProvider);
  return ChainedIsbnLookup(
    primary: OpenLibraryLookupService(client: client),
    fallback: GoogleBooksLookupService(
      client: client,
      // Read per-request: a key saved in Settings applies immediately.
      apiKey: keys.googleBooksApiKey,
    ),
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
    // Downscale before publishing (400x600 q80): small git push AND EXIF/GPS
    // stripped. No raw fallback — a cover that can't be re-encoded is
    // dropped, never published unstripped (REVIEW_FINDINGS_2 S11).
    return ImageDownscaler.downscaleJpeg(raw);
  };
}

/// Local cover-file reader for publishing (N14): the file IO the publish
/// controller used to do itself (dart:io in the application layer). Injected
/// as a function port, rooted at the app's covers directory.
@riverpod
Future<Future<List<int>?> Function(String)> publishLocalCoverReader(
  PublishLocalCoverReaderRef ref,
) async {
  final coversDir = await ref.watch(coversDirProvider.future);
  return localCoverReader(coversDir);
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
/// Expose the port so tests can substitute an in-memory store without file IO.
@riverpod
Future<PublishManifestGateway> publishManifestStore(
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

/// Count of currently-visible passphrase entry fields (vault create / unlock
/// / change-passphrase / restore flows). Incremented by
/// `SecurePassphraseField.initState`, decremented on dispose.
///
/// keepAlive is deliberate: the field captures this notifier in initState and
/// calls it again from dispose(), which is only safe if the notifier can
/// never be auto-disposed out from under the widget.
@Riverpod(keepAlive: true)
class PassphraseEntryVisibility extends _$PassphraseEntryVisibility {
  @override
  int build() => 0;

  /// A passphrase field appeared on screen.
  void markVisible() => state = state + 1;

  /// A passphrase field left the screen. Clamped at zero: an unbalanced call
  /// is a caller bug, but it must never drive the count negative (that would
  /// silently turn protection OFF later — fail closed).
  void markHidden() => state = state > 0 ? state - 1 : 0;
}

/// Single source of truth for the window FLAG_SECURE policy: ON when the
/// vault is unlocked (borrower PII visible) OR any passphrase entry field is
/// visible (#34/F-12 + REVIEW_FINDINGS_2 S2). main.dart listens to this and
/// drives [screenSecurityProvider] — one decision point, so the page-level
/// and vault-level signals can never race each other.
@riverpod
bool screenCaptureProtected(ScreenCaptureProtectedRef ref) {
  final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
  final entering = ref.watch(passphraseEntryVisibilityProvider) > 0;
  return shouldSecureForState(
    session ?? const VaultUninitialized(),
    passphraseEntryVisible: entering,
  );
}

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

/// Sealed, authentication-bound store for the biometric secret S (#34 B2,
/// M08). S is the only thing persisted for biometric unlock; the passphrase is
/// never stored. On Android the store encrypts S under a Keystore key that
/// requires a fresh strong-biometric authentication per use; on any platform
/// without the native handler it fails closed ("not available").
@riverpod
BiometricKeyStore biometricKeyStore(BiometricKeyStoreRef ref) =>
    KeystoreBiometricSecretVault();

/// At-rest store for the persistent on-device vault (DB path + wrapped-key
/// blob), rooted inside the active data generation (M02; was the app documents
/// dir before, #26.2, Q-26b).
@riverpod
Future<VaultStore> vaultStore(VaultStoreRef ref) async {
  final generation = await ref.watch(activeDataGenerationProvider.future);
  return VaultStore(baseDir: generation.vaultDir);
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

/// Loan-row read model (N06): resolves the catalogue title of a loaned book
/// so borrower screens show the book's name instead of the internal row id.
/// Null when the book no longer exists (the UI falls back to "Book #id").
@riverpod
Future<String?> bookTitle(BookTitleRef ref, {required int bookId}) async {
  final repo = await ref.watch(bookRepositoryProvider.future);
  final book = (await repo.getById(bookId)).toNullable();
  return book?.title;
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

/// Side-effect-free bundle decoding, exposed through its domain contract.
@riverpod
Future<BundleReader> libraryBundleReader(LibraryBundleReaderRef ref) async =>
    const LibraryBundleReader();

/// Operation-owned imported covers under the existing app-private covers dir.
@riverpod
Future<BundleCoverFiles> bundleCoverFiles(BundleCoverFilesRef ref) async =>
    FileBundleCoverStore(coversDir: await ref.watch(coversDirProvider.future));

/// One-shot library/wishlist import use case.
@riverpod
Future<ImportLibraryUseCase> importLibraryUseCase(
  ImportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ImportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    // N14: the concrete JSON codec is infrastructure, wired here at the
    // composition root.
    jsonParser: const PitakaJsonImporter(),
  );
}

/// Library-logo file reader for exports (N14): file IO injected as a port;
/// the application controller no longer touches dart:io.
@riverpod
Future<Future<Uint8List?> Function(String)> exportLogoReader(
  ExportLogoReaderRef ref,
) async {
  final coversDir = await ref.watch(coversDirProvider.future);
  return logoFileReader(coversDir);
}

/// Event-poster file reader for publishing (N14): file IO injected as the
/// `PosterBytesReader` port; the events controller no longer touches dart:io.
@riverpod
Future<Future<List<int>?> Function(String)> eventsPosterReader(
  EventsPosterReaderRef ref,
) async {
  final dir = await ref.watch(appDocsDirProvider.future);
  return posterFileReader(dir.path);
}

/// One-shot library/wishlist export use case.
@riverpod
Future<ExportLibraryUseCase> exportLibraryUseCase(
  ExportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ExportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    jsonEncoder: const PitakaJsonExporter(),
    pdfRenderer: const PdfLibraryRenderer(),
  );
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
  return MergeLibraryUseCase(
    bookRepo: bookRepo,
    settings: settings,
    jsonParser: const PitakaJsonImporter(),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
  );
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
  final coversDir = await ref.watch(coversDirProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  final writer = BackupArchiveWriter(
    openDatabase: sqlite3.open,
    vaultStore: store,
    coversDir: coversDir,
  );
  return CreateBackupUseCase(
    books: books,
    wishlist: wishlist,
    writer: writer,
    workDir: p.join(dir.path, 'backup_create_work'),
  );
}

/// Backup-archive restorer (authoritative overwrite of local state).
///
/// M02: restore builds a NEW data generation and switches to it atomically
/// through [ActiveDataGeneration.activate], which republishes the paths so the
/// database, covers and vault-store providers all rebuild onto the new set.
/// The active generation is resolved lazily (`ref.read` at call time), not
/// watched: watching would rebuild this restorer mid-switch for no benefit.
@riverpod
Future<RestoreBackup> restoreBackup(RestoreBackupRef ref) async {
  final vault = ref.watch(vaultRepositoryProvider);
  final generations = await ref.watch(dataGenerationsProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  return RestoreBackup(
    vault: vault,
    generations: generations,
    activeGeneration: () => ref.read(activeDataGenerationProvider.future),
    activate: (generation) =>
        ref.read(activeDataGenerationProvider.notifier).activate(generation),
    workDir: p.join(dir.path, 'restore_work'),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
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
