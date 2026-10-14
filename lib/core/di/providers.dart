/// Dependency-injection providers (AGENTS.md §4: Riverpod codegen is the DI
/// container — no GetIt, no service locators).
///
/// The non-secret Drift database and the repositories/use cases over it are
/// wired here. The encrypted vault is reached through the Rust FFI core via
/// [vaultRepository]; the vault key never enters Dart.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
// S3: providers live in per-feature modules under `src/`; this file imports
// the modules its remaining declarations reference AND re-exports all of
// them, so every call site keeps importing `core/di/providers.dart`.
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/vault_providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/app_update/domain/app_update_service.dart';
import 'package:pitaka/features/app_update/infrastructure/play_app_update_service.dart';
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
import 'package:pitaka/features/import_export/infrastructure/background_merge_planner.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/logo_file_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart'
    hide PdfTextRasterizer, RasterizedText;
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/lookup/application/chained_isbn_lookup.dart';
import 'package:pitaka/features/lookup/domain/isbn_cache.dart';
import 'package:pitaka/features/lookup/domain/isbn_lookup_service.dart';
import 'package:pitaka/features/lookup/domain/lookup_key_store.dart';
import 'package:pitaka/features/lookup/infrastructure/google_books_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/in_memory_isbn_cache.dart';
import 'package:pitaka/features/lookup/infrastructure/open_library_lookup_service.dart';
import 'package:pitaka/features/lookup/infrastructure/secure_storage_lookup_key_store.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:pitaka/core/di/src/database_providers.dart';
export 'package:pitaka/core/di/src/library_providers.dart';
export 'package:pitaka/core/di/src/platform_providers.dart';
export 'package:pitaka/core/di/src/publish_providers.dart';
export 'package:pitaka/core/di/src/settings_providers.dart';
export 'package:pitaka/core/di/src/vault_providers.dart';

part 'providers.g.dart';

/// Library-bookmarks persistence (other libraries' published sites). Non-secret
/// flat list in shared_preferences — no Drift table/migration.
@riverpod
Future<BookmarksRepository> bookmarksRepository(
  BookmarksRepositoryRef ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return PrefsBookmarksRepository(prefs);
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

/// Session-scoped ISBN lookup cache (#30). Non-secret public metadata.
@Riverpod(keepAlive: true)
IsbnCache isbnCache(IsbnCacheRef ref) => InMemoryIsbnCache();

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

/// The Play in-app update seam (S35). The real service gates itself to
/// Android + the `play` applicationId (the fdroid flavor has no Play listing
/// and stays inert) and degrades to silence on every platform failure.
/// Overridden with a fake in tests.
@riverpod
AppUpdateService appUpdateService(AppUpdateServiceRef ref) =>
    const PlayAppUpdateService(appInfo: MethodChannelAppInfo());

/// One wishlist entry, observed by id, for its detail screen (N03).
/// Same shape and rationale as [bookById]; the freshness signal is
/// [wishlistControllerProvider], which every wishlist mutation refreshes.
@riverpod
Future<WishlistBook?> wishlistBookById(
  WishlistBookByIdRef ref,
  int bookId,
) async {
  ref.watch(wishlistControllerProvider);
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  final result = await repo.getById(bookId);
  return result.fold(
    // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
    (failure) => throw failure,
    (book) => book,
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
/// gate. The library identity (ID gate + Join/Overwrite adoption) goes through
/// `SettingsController` — the single serialised settings writer — via the
/// `LibraryNamespace` port, so the drawer/title/export name update the moment
/// a merge adopts a library (N07; same shape as the replacement guard below).
@riverpod
Future<MergeLibraryUseCase> mergeLibraryUseCase(
  MergeLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  return MergeLibraryUseCase(
    bookRepo: bookRepo,
    namespace: ref.read(settingsControllerProvider.notifier),
    jsonParser: const PitakaJsonImporter(),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
    // N10-c: the plan is computed on a worker isolate.
    planner: planMergeInBackground,
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
  // N10-c: the writer opens SQLite itself inside its worker isolate (an
  // `sqlite3.open` tear-off is not sendable across isolates).
  final writer = BackupArchiveWriter(vaultStore: store, coversDir: coversDir);
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
        ImageDownscaler.downscaleJpegAsync(bytes, maxW: 1080, maxH: 1440),
  );
}
