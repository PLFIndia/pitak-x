/// Share Apps bottom sheet (presentation, AGENTS.md §3.1).
///
/// Every row shares only that app's validated Play Store link through the
/// existing FileShareService seam. The ListView shrinks around one app today
/// and scrolls when the catalog grows beyond the available screen height.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/share_apps/presentation/share_apps_catalog.dart';

/// Opens the Share Apps panel.
Future<void> showShareAppsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const ShareAppsSheet(),
  );
}

/// The shareable-app list. Public so widget tests can pump it directly.
class ShareAppsSheet extends ConsumerWidget {
  /// Creates the panel from the shared app catalog.
  const ShareAppsSheet({super.key});

  Future<void> _shareApp(
    BuildContext context,
    WidgetRef ref,
    ShareAppEntry entry,
  ) async {
    final outcome = await ref
        .read(fileShareServiceProvider)
        .shareText(entry.app.playStoreUrl);
    if (!context.mounted) return;

    // Keep this panel open after sharing: once more apps are listed, the user
    // may want to share another one without navigating back through the drawer.
    if (outcome == ShareOutcome.unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing is not available on this device.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text('Share Apps', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final entry in shareAppCatalog)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              backgroundImage: AssetImage(entry.iconAssetPath),
            ),
            title: Text(entry.app.name),
            trailing: IconButton(
              tooltip: 'Share ${entry.app.name}',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareApp(context, ref, entry),
            ),
          ),
      ],
    );
  }
}
