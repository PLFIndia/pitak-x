/// App navigation drawer (presentation, AGENTS.md §3.1).
///
/// Layout: the library header (logo + name) is pinned at the top, the primary
/// destinations (Vault, Publish, Wishlist, Bookmarks) scroll in the middle, and
/// Settings is pinned to the bottom edge. Data operations (import/export/backup/
/// restore) live under Settings → Data, so the drawer stays a short, stable
/// list of top-level places. Each tile closes the drawer and pushes the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/features/bookmarks/presentation/pages/bookmarks_page.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';
import 'package:pitaka/features/wishlist/presentation/pages/wishlist_page.dart';

/// The primary navigation drawer.
class AppDrawer extends ConsumerWidget {
  /// Creates the drawer.
  const AppDrawer({super.key});

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Show the user's library name in the header when set; else the app name.
    final libraryName = ref
        .watch(settingsControllerProvider)
        .maybeWhen(data: (s) => s.libraryName.trim(), orElse: () => '');
    final headerTitle = libraryName.isEmpty ? 'Pitak' : libraryName;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pinned top: library logo + name. A compact, content-sized header
            // (not a fixed-height DrawerHeader slab): no colour block and no
            // dead space above the logo. A divider separates it from the list.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              child: Row(
                children: [
                  const LibraryLogo(size: 48, borderRadius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      headerTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable middle: the primary destinations.
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Borrowers vault'),
                    onTap: () => _go(context, const VaultPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Publish to web'),
                    onTap: () => _go(context, const PublishPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: const Text('Wishlist'),
                    onTap: () => _go(context, const WishlistPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: const Text('Bookmarks'),
                    onTap: () => _go(context, const BookmarksPage()),
                  ),
                  // Shown only once a site exists (published at least once):
                  // a share button with nothing to share would be a dead end.
                  if (ref.watch(publishedSiteUrlProvider).valueOrNull
                      case final String siteUrl)
                    ListTile(
                      leading: const Icon(Icons.ios_share),
                      title: const Text('Share Library Website'),
                      onTap: () {
                        Navigator.of(context).pop(); // close the drawer
                        // Through the FileShareService seam so tests can
                        // fake the OS share sheet.
                        ref.read(fileShareServiceProvider).shareText(siteUrl);
                      },
                    ),
                ],
              ),
            ),
            // Pinned bottom: Settings.
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => _go(context, const SettingsPage()),
            ),
          ],
        ),
      ),
    );
  }
}
