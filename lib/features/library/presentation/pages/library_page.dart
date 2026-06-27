/// Library list + search screen (presentation layer, AGENTS.md §3.1).
///
/// Pure presentation: reads [LibraryController] state and forwards user input
/// to it. No business logic, no direct repository/DB access. Mirrors the Kotlin
/// `LibraryScreen` (search field, row list, empty state) minus the features
/// deferred for this slice (sort/filter facets, vault availability badge, cover
/// images — see PLAN.md Step 11 out-of-scope).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/layout/breakpoints.dart';
import 'package:pitaka/core/widgets/app_drawer.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/library/presentation/pages/book_detail_page.dart';
import 'package:pitaka/features/library/presentation/widgets/book_grid_card.dart';
import 'package:pitaka/features/library/presentation/widgets/book_row.dart';
import 'package:pitaka/features/library/presentation/widgets/empty_library_state.dart';
import 'package:pitaka/features/library/presentation/widgets/library_controls_row.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/domain/availability.dart';

/// The library list screen with a debounced search field.
class LibraryPage extends ConsumerWidget {
  /// Creates the library page.
  const LibraryPage({super.key});

  /// Quick-add (Q2=A): scan a barcode, then open the Add-Book form with the
  /// ISBN pre-filled. The user reviews, taps Lookup, and saves — scanning never
  /// creates a book on its own.
  Future<void> _quickAddByScan(BuildContext context) async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (scanned == null || !context.mounted) return;
    final isbn = IsbnFormat.normalize(scanned);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddBookPage(initialIsbn: isbn)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(libraryControllerProvider.notifier);
    final booksAsync = ref.watch(libraryControllerProvider);
    // Use the user's library name as the title, falling back to 'Library'.
    final libraryName = ref
        .watch(settingsControllerProvider)
        .maybeWhen(data: (s) => s.libraryName, orElse: () => '');

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
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan to add',
            onPressed: () => _quickAddByScan(context),
          ),
          IconButton(
            icon: const Icon(Icons.campaign_outlined),
            tooltip: 'Events',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EventsPage()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'backup') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreateBackupPage(),
                  ),
                );
              } else if (value == 'restore') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RestorePage()),
                );
              } else if (value == 'import') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportPage()),
                );
              } else if (value == 'export') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ExportPage()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'import', child: Text('Import')),
              PopupMenuItem(value: 'export', child: Text('Export')),
              PopupMenuItem(value: 'backup', child: Text('Create backup')),
              PopupMenuItem(value: 'restore', child: Text('Restore backup')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AddBookPage())),
        tooltip: 'Add book',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: controller.onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search title, author, ISBN…',
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
                isSearching: controller.query.trim().isNotEmpty,
                onRetry: controller.refresh,
              ),
              data: (books) => books.isEmpty
                  ? EmptyLibraryState(
                      isSearching: controller.query.trim().isNotEmpty,
                      query: controller.query,
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
                  : _BookList(books: books),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookList extends ConsumerWidget {
  const _BookList({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Active-loan counts are non-null only when the vault is unlocked; the
    // "Not available" badge is hidden otherwise (availability unknown).
    final activeCounts = ref.watch(activeLoanCountsProvider);

    bool unavailableOf(Book book) =>
        activeCounts != null &&
        isBookUnavailable(
          bookId: book.id,
          copyCount: book.copyCount,
          activeCounts: activeCounts,
        );
    void openDetail(Book book) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: book)));

    // Adaptive layout: decide on the *available width* the parent gives us, not
    // the device type — a single column on phones, a cover grid once there is
    // room for it (tablets, foldables, resized desktop windows).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= largeScreenMinWidth) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              // Target column width; Flutter picks the column count that fits.
              maxCrossAxisExtent: 200,
              mainAxisExtent: 280,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return BookGridCard(
                book: book,
                unavailable: unavailableOf(book),
                onTap: () => openDetail(book),
              );
            },
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: books.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final book = books[index];
            return BookRow(
              book: book,
              unavailable: unavailableOf(book),
              onTap: () => openDetail(book),
            );
          },
        );
      },
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
