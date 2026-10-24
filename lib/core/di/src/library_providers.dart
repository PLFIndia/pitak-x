/// Library-feature DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the book repository, cover store/coordinator/janitor,
/// the library read models and the add/update/delete use cases plus the
/// post-scan barcode router (ADR 0013 D11).
///
/// Cross-feature note (beginner): the delete use case purges VAULT loans,
/// but it receives that capability through a narrow port (`VaultLoanPurger`)
/// satisfied by the vault session controller — so this module imports the
/// vault feature's APPLICATION file (where the controller's own `@riverpod`
/// lives), never the vault DI module. One direction, no cycles.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/settings_providers.dart';
import 'package:pitaka/features/library/application/add_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/application/delete_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/route_scanned_barcode_use_case.dart';
import 'package:pitaka/features/library/application/update_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/cover_files.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_providers.g.dart';

/// Library books repository.
@riverpod
Future<CatalogueItemRepository> catalogueItemRepository(
  CatalogueItemRepositoryRef ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCatalogueItemRepository(db);
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
  final books = await ref.watch(catalogueItemRepositoryProvider.future);
  // M11: wishlist rows reference covers in the same directory; the janitor
  // must count them as live references or startup sweeps delete their art.
  final wishlist = await ref.watch(wishlistRepositoryProvider.future);
  // W4 (ADR 0014): a periodical's series cover is a live reference too.
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final store = await ref.watch(coverStoreProvider.future);
  return CoverFileJanitor(
    books: books,
    wishlist: wishlist,
    periodicals: periodicals,
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
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [catalogueItemById]) — watching only the repository OBJECT never
/// fires, so without this an add/edit/import/restore left the chips stale.
@riverpod
Future<List<String>> libraryLanguages(LibraryLanguagesRef ref) async {
  ref.watch(libraryControllerProvider);
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  final result = await repo.distinctLanguages();
  return result.getOrElse((_) => const []);
}

/// Distinct non-blank source details (donor / seller names…) recorded under
/// one [ItemSourceType] — the Export screen's "source detail" picker values.
///
/// Same freshness rule as [libraryLanguages]: watches
/// [libraryControllerProvider] as the mutation signal so an edit that renames
/// a donor is reflected the next time the picker opens. A repository failure
/// degrades to an empty list — the picker then offers "Any", and the export
/// itself still runs; nothing here is worth blocking the screen for.
@riverpod
Future<List<String>> librarySourceDetails(
  LibrarySourceDetailsRef ref,
  ItemSourceType type,
) async {
  ref.watch(libraryControllerProvider);
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  final result = await repo.distinctSourceDetails(type);
  return result.getOrElse((_) => const []);
}

/// Adds a new book to the library (title-required validation + persist).
@riverpod
Future<AddCatalogueItemUseCase> addCatalogueItemUseCase(
  AddCatalogueItemUseCaseRef ref,
) async {
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  return AddCatalogueItemUseCase(repo);
}

/// Decides where a scanned barcode takes the user (ADR 0013 D11): a `977`
/// magazine code routes by ISSN to the add-issue flow or a new title; any
/// other code takes the ISBN path (existing item or the add-book form).
@riverpod
Future<RouteScannedBarcodeUseCase> routeScannedBarcodeUseCase(
  RouteScannedBarcodeUseCaseRef ref,
) async {
  final items = await ref.watch(catalogueItemRepositoryProvider.future);
  final periodicals = await ref.watch(periodicalRepositoryProvider.future);
  return RouteScannedBarcodeUseCase(items: items, periodicals: periodicals);
}

/// Updates an existing library book (title-required, id-immutable).
@riverpod
Future<UpdateCatalogueItemUseCase> updateCatalogueItemUseCase(
  UpdateCatalogueItemUseCaseRef ref,
) async {
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  return UpdateCatalogueItemUseCase(repo);
}

/// Hard-deletes a library book, purging its vault loans when unlocked (#27/D3).
/// The vault side is the session controller (it satisfies [VaultLoanPurger]).
@riverpod
Future<DeleteCatalogueItemUseCase> deleteCatalogueItemUseCase(
  DeleteCatalogueItemUseCaseRef ref,
) async {
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  final vault = ref.read(vaultSessionControllerProvider.notifier);
  final janitor = await ref.watch(coverFileJanitorProvider.future);
  return DeleteCatalogueItemUseCase(
    books: repo,
    vault: vault,
    releaseCover: janitor.releaseReference,
  );
}

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `CatalogueItem` the list row was tapped with: a
/// detail page can stay open while the row changes underneath it — a cover
/// captured on that very page rewrites `coverUrl`, the remote-cover
/// materializer may swap an `https://` reference for a local file, an edit
/// saves new fields. A snapshot handed in at push time never learns any of
/// this, and passing it on to the edit form wrote stale values back over the
/// fresh row (a cover file the janitor had already deleted came back as the
/// row's cover).
///
/// Freshness signal: every mutation path in the app already invalidates or
/// refreshes [libraryControllerProvider] (cover replace, materializer, edit
/// save, remove/restore, import, restore, wishlist move). Watching it here —
/// value ignored — makes this provider re-read the row on the same signal,
/// with no new plumbing. The repository has no row streams (N04); when it
/// gains one this dependency is the single line to swap.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError` (same idiom as `LibraryController._load`).
@riverpod
Future<CatalogueItem?> catalogueItemById(
  CatalogueItemByIdRef ref,
  int bookId,
) async {
  ref.watch(libraryControllerProvider);
  final repo = await ref.watch(catalogueItemRepositoryProvider.future);
  final result = await repo.getById(bookId);
  return result.fold(
    // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
    (failure) => throw failure,
    (book) => book,
  );
}
