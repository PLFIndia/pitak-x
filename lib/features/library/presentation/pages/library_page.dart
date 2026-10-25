/// Library list + search screen (presentation layer, AGENTS.md §3.1).
///
/// Pure presentation: reads [LibraryController] state and forwards user input
/// to it. No business logic, no direct repository/DB access. Mirrors the Kotlin
/// `LibraryScreen` (search field, sort/filter controls, row list with covers,
/// empty state).
///
/// N10-d part 2: the list renders the controller's [LibraryWindow] — the rows
/// loaded so far — and asks for the next window as the user nears the end
/// (`loadMore`), with a footer indicator while it is in flight. The screen
/// never holds the whole catalogue.
///
/// S14: the app-bar overflow menu moved to `widgets/library_menu_button.dart`;
/// the quick-add scan now routes through [RouteScannedBarcodeUseCase] (ADR
/// 0013 D11) — the page only switches on the sealed [ScanRoute].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/layout/breakpoints.dart';
import 'package:pitaka/core/widgets/app_drawer.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/features/app_update/presentation/widgets/app_update_banner.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_filter_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/application/route_scanned_barcode_use_case.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/library/presentation/widgets/add_sheet.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_row.dart';
import 'package:pitaka/features/library/presentation/widgets/empty_library_state.dart';
import 'package:pitaka/features/library/presentation/widgets/library_controls_row.dart';
import 'package:pitaka/features/library/presentation/widgets/library_menu_button.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/domain/availability.dart';

/// The library list screen with a debounced search field.
class LibraryPage extends ConsumerStatefulWidget {
  /// Creates the library page.
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// The page owns the visible field's value so Clear search can empty it
  /// immediately. Disposing it here avoids leaking one controller per visit.
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    // TextEditingController.clear does not call TextField.onChanged, so emit
    // the empty query explicitly while leaving both facet providers intact.
    ref.read(libraryControllerProvider.notifier).onQueryChanged('');
  }

  void _clearFilters() {
    // Independent of Clear search: only the two facets reset; the visible
    // query and LibraryController's debounced query remain untouched.
    ref.read(libraryLanguageFilterProvider.notifier).clear();
    ref.read(libraryKindFilterProvider.notifier).clear();
  }

  /// Quick-add (Q2=A): scan a barcode, then route it (S34, ADR 0013 D11).
  /// Scanning never creates a row on its own — the route decides which
  /// existing row, form, or placeholder the scan leads to.
  Future<void> _quickAddByScan() async {
    // Resolve the use case BEFORE the camera flow: no `ref` use after an
    // async gap that could outlive this widget instance.
    final route = await ref.read(routeScannedBarcodeUseCaseProvider.future);
    if (!mounted) return;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (scanned == null || !mounted) return;
    await routeScannedBarcode(context, route, scanned);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(libraryControllerProvider.notifier);
    final booksAsync = ref.watch(libraryControllerProvider);
    final hasQuery = controller.query.trim().isNotEmpty;
    // Facets are independent provider state (the same source as the chips).
    // Watching them here keeps the empty-state explanation and recovery
    // buttons truthful immediately after a chip is tapped or cleared.
    final hasKindFilter = ref.watch(libraryKindFilterProvider) != null;
    final hasLanguageFilter = ref.watch(libraryLanguageFilterProvider) != null;
    final hasFilters = hasKindFilter || hasLanguageFilter;
    // Use the user's library name as the title (select: only that field
    // rebuilds this page, §8), falling back to 'Library'.
    final libraryName = ref.watch(
      settingsControllerProvider.select(
        (s) => s.maybeWhen(data: (st) => st.libraryName, orElse: () => ''),
      ),
    );
    // Housekeeping (decision Q12): once the list has loaded for the first
    // time this session, sweep cover files nothing references any more. The
    // keepAlive provider makes this a genuine one-shot; `listen` (not watch)
    // so the sweep's completion never rebuilds the page.
    if (booksAsync.hasValue) {
      ref.listen(orphanCoverSweepProvider, (_, _) {});
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        // The library logo (or default Pitak icon) doubles as the drawer
        // button, replacing the default hamburger. Tap opens the side panel.
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const LibraryLogo(size: 32),
          ),
        ),
        title: Text(libraryName.isEmpty ? 'Library' : libraryName),
        actions: [
          // Shortcut to the network map (the Map tab is consent-gated — it
          // asks there, not here).
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Network map',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NetworkPage(initialTab: 1),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan to add',
            onPressed: _quickAddByScan,
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Events',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const PublishPage(initialTab: PublishTab.events),
              ),
            ),
          ),
          const LibraryMenuButton(),
        ],
      ),
      floatingActionButton: const AddSheetFab(),
      body: Column(
        children: [
          // S35: Play flexible-update banner — renders zero-height unless
          // this is a play-flavor Android install with a download running
          // or finished (ineligible/idle → SizedBox.shrink).
          const AppUpdateBanner(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: controller.onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search title, author, ISBN, notes…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const LibraryControlsRow(),
          Expanded(
            child: booksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (error, _) => _LibraryError(
                isSearching: hasQuery,
                onRetry: controller.refresh,
              ),
              data: (window) => window.books.isEmpty
                  ? EmptyLibraryState(
                      hasQuery: hasQuery,
                      hasFilters: hasFilters,
                      onClearSearch: _clearSearch,
                      onClearFilters: _clearFilters,
                      onAdd: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AddBookPage(),
                        ),
                      ),
                      onImport: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ImportPage(),
                        ),
                      ),
                    )
                  : _BookList(window: window, onLoadMore: controller.loadMore),
            ),
          ),
        ],
      ),
    );
  }
}

/// How close to the end (in logical pixels of remaining scroll extent) the
/// next page is requested — about one and a half phone screens ahead, so the
/// rows are usually there before the user reaches them.
const double _loadMoreThreshold = 600;

/// Key of the footer indicator shown while the next page is in flight
/// (tests locate it by this key).
const _loadMoreKey = ValueKey('library-load-more');

class _BookList extends ConsumerWidget {
  const _BookList({required this.window, required this.onLoadMore});

  final LibraryWindow window;
  final Future<void> Function() onLoadMore;

  /// Asks for the next window when the user is near the end. The controller
  /// de-duplicates concurrent calls and ignores it once nothing is left, so
  /// firing on every notification is cheap and safe.
  bool _onScroll(ScrollNotification notification) {
    if (window.hasMore &&
        !window.isLoadingMore &&
        notification.metrics.extentAfter < _loadMoreThreshold) {
      onLoadMore();
    }
    return false; // let the notification keep bubbling
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = window.books;
    // Active-loan counts are non-null only when the vault is unlocked; the
    // "Not available" badge is hidden otherwise (availability unknown).
    final activeCounts = ref.watch(activeLoanCountsProvider);

    bool unavailableOf(CatalogueItem book) =>
        activeCounts != null &&
        isBookUnavailable(
          bookId: book.id,
          copyCount: book.copyCount,
          activeCounts: activeCounts,
        );
    // N03: the detail page observes the row by id; the tapped row is only the
    // first frame's content.
    void openDetail(CatalogueItem book) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CatalogueItemDetailPage(bookId: book.id, initialBook: book),
      ),
    );

    // Footer: a small progress row while the next page is in flight. Rendered
    // as its own sliver after the rows so both layouts share it.
    final footer = SliverToBoxAdapter(
      child: window.isLoadingMore
          ? const Padding(
              key: _loadMoreKey,
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          : const SizedBox.shrink(),
    );

    // Adaptive layout: decide on the *available width* the parent gives us, not
    // the device type — a single column on phones, a cover grid once there is
    // room for it (tablets, foldables, resized desktop windows).
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= largeScreenMinWidth) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          // Target column width; Flutter picks the column
                          // count that fits.
                          maxCrossAxisExtent: 200,
                          mainAxisExtent: 280,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return CatalogueItemGridCard(
                        book: book,
                        unavailable: unavailableOf(book),
                        onTap: () => openDetail(book),
                      );
                    },
                  ),
                ),
                footer,
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                sliver: SliverList.separated(
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return CatalogueItemRow(
                      book: book,
                      unavailable: unavailableOf(book),
                      onTap: () => openDetail(book),
                    );
                  },
                ),
              ),
              footer,
            ],
          );
        },
      ),
    );
  }
}

/// Post-scan routing (S34 + ADR 0013 D11): the page's side of
/// [RouteScannedBarcodeUseCase], extracted so it is testable without a camera.
///
/// The use case already decided WHERE the raw scan leads; this function only
/// turns the sealed [ScanRoute] into a navigation step:
///
/// - [OpenCataloguedItem] → the "already in your library" dialog offering the
///   EXISTING row — filling in a form the UNIQUE isbn index would refuse to
///   save is wasted work and a confusing error;
/// - [AddBookByIsbn] → the add-book form pre-filled;
/// - [AddIssueOfPeriodical] → the add-issue form with the series preselected;
/// - [OpenPeriodical] → the removed series' detail, where it can be restored;
/// - [AddPeriodicalByIssn] → the series form with the scanned ISSN pre-filled
///   (both S16 forms; the ISSN identifies the TITLE, never the issue — D7).
Future<void> routeScannedBarcode(
  BuildContext context,
  RouteScannedBarcodeUseCase useCase,
  String raw,
) async {
  final route = await useCase(raw);
  if (!context.mounted) return;
  switch (route) {
    case OpenCataloguedItem(item: final found):
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already in your library'),
          content: Text("'${found.title}' is already in your library."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('View item'),
            ),
          ],
        ),
      );
      if ((open ?? false) && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CatalogueItemDetailPage(bookId: found.id, initialBook: found),
          ),
        );
      }
    case AddBookByIsbn(isbn: final isbn):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => AddBookPage(initialIsbn: isbn)),
      );
    case AddIssueOfPeriodical(periodical: final periodical):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddIssuePage(periodical: periodical),
        ),
      );
    case OpenPeriodical(periodical: final periodical):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PeriodicalDetailPage(
            periodicalId: periodical.id,
            initialPeriodical: periodical,
          ),
        ),
      );
    case AddPeriodicalByIssn(issn: final issn):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PeriodicalFormPage(initialIssn: issn),
        ),
      );
  }
}

/// Safe error state — never shows raw exception text (AGENTS.md §5).
class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.isSearching, required this.onRetry});

  final bool isSearching;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final message = isSearching
        ? "Couldn't run that search. Please try again."
        : "Couldn't load your library. Please try again.";
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
