/// Standalone saved-libraries page for bookmarks added by published site URL.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/presentation/widgets/add_library_dialog.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/saved_libraries_view.dart';

/// The main-drawer Library Bookmarks destination.
class LibraryBookmarksPage extends ConsumerWidget {
  /// Creates the page with an injectable browser seam for viewer tests.
  const LibraryBookmarksPage({
    super.key,
    this.publishedSiteOpener = const PublishedSiteOpener(),
  });

  /// Forwarded to the native published-catalogue viewer.
  final PublishedSiteOpener publishedSiteOpener;

  Future<void> _addBookmark(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (_) => const AddLibraryDialog(),
    );
    if (result == null || !context.mounted) return;

    // AddLibraryDialog validates for immediate feedback; the controller
    // re-validates the untrusted URL and name at the application boundary.
    final outcome = await ref
        .read(networkControllerProvider.notifier)
        .addByUrl(url: result.url, name: result.name);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          NetworkAddOutcome.added =>
            'Library added. Tap Refresh to fetch its details.',
          NetworkAddOutcome.alreadySaved => 'That library is already saved.',
          NetworkAddOutcome.invalidUrl =>
            'That link was not accepted. Use a GitHub Pages, Cloudflare '
                'Pages or Cloudflare Workers address.',
          NetworkAddOutcome.storageFailed => "Couldn't add that library.",
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library Bookmarks')),
      body: SavedLibrariesView(
        opener: publishedSiteOpener,
        emptyStateHint:
            'Tap "Add Bookmark" to save a library by its web address.',
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'libraryBookmarksAddBookmark',
        onPressed: () => _addBookmark(context, ref),
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Add Bookmark'),
      ),
    );
  }
}
