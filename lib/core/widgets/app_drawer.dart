/// App navigation drawer (presentation, AGENTS.md §3.1).
///
/// Left edge-swipe / hamburger drawer holding the four primary destinations:
/// Borrowers vault, Publish, Wishlist, and Settings. Data operations
/// (import/export/backup/restore) live under Settings → Data, so the drawer
/// stays a short, stable list of top-level places. Each tile closes the drawer
/// and pushes the destination page.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';
import 'package:pitaka/features/wishlist/presentation/pages/wishlist_page.dart';

/// The primary navigation drawer.
class AppDrawer extends StatelessWidget {
  /// Creates the drawer.
  const AppDrawer({super.key});

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: scheme.primaryContainer),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LibraryLogo(size: 48, borderRadius: 12),
                    const SizedBox(width: 12),
                    Text(
                      'Pitak',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
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
            const Divider(),
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
