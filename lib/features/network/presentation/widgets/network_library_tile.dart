/// One saved library in the network list (presentation, libNetwork.md §5.1).
///
/// Deliberately thin: name (or the URL when a row has no name yet), the site
/// address, the shared [MembershipBadge] row, and tap-to-open in the external
/// browser (the same rule the old bookmarks had: validated Pages links only,
/// never an in-app webview).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// A list tile for one [NetworkLibrary] row.
class NetworkLibraryTile extends StatelessWidget {
  /// Creates the tile. [onRemove] null hides the remove action.
  const NetworkLibraryTile({required this.row, this.onRemove, super.key});

  /// The row to render.
  final NetworkLibrary row;

  /// Called when the user asks to remove the row.
  final VoidCallback? onRemove;

  /// Opens the row's site in the device browser (external application —
  /// untrusted third-party pages never render inside the app's process).
  Future<void> openSite(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(row.siteUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = row.name.isEmpty ? row.siteUrl : row.name;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.public),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (row.name.isNotEmpty)
              Text(
                row.siteUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            MembershipBadge(row),
          ],
        ),
        isThreeLine: row.name.isNotEmpty,
        trailing: onRemove == null
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
        onTap: () => openSite(context),
      ),
    );
  }
}
