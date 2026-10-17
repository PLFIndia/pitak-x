/// One saved library in the network list (presentation, libNetwork.md §5.1).
///
/// Deliberately thin: name (or the URL when a row has no name yet), the site
/// address, the shared [MembershipBadge] row, and tap-to-open in the external
/// browser (the same rule the old bookmarks had: validated Pages links only,
/// never an in-app webview).
///
/// The member→hub prompt (§5.6 step 4) lives HERE, inline under its row:
/// a `pending` row asks "show that you're a member?" with plain Confirm /
/// Not-now buttons, and a `declined` row keeps a quiet "Reconsider" action —
/// the user is never re-prompted automatically, but the door stays open.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// A list tile for one [NetworkLibrary] row.
class NetworkLibraryTile extends StatelessWidget {
  /// Creates the tile. [onRemove] null hides the remove action; the
  /// membership callbacks null hide the prompt/Reconsider actions (e.g. in
  /// previews and goldens).
  const NetworkLibraryTile({
    required this.row,
    this.onRemove,
    this.onConfirmMembership,
    this.onDeclineMembership,
    this.onReconsiderMembership,
    super.key,
  });

  /// The row to render.
  final NetworkLibrary row;

  /// Called when the user asks to remove the row.
  final VoidCallback? onRemove;

  /// Called when the user answers the pending-membership prompt "yes".
  final VoidCallback? onConfirmMembership;

  /// Called when the user answers the pending-membership prompt "not now".
  final VoidCallback? onDeclineMembership;

  /// Called when the user taps "Reconsider" on a declined membership.
  final VoidCallback? onReconsiderMembership;

  /// Display title: the name when known, else the site URL.
  String get title => row.name.isEmpty ? row.siteUrl : row.name;

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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
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
          if (row.membership == MembershipState.pending &&
              onConfirmMembership != null &&
              onDeclineMembership != null)
            _MembershipPrompt(
              title: title,
              onConfirm: onConfirmMembership!,
              onDecline: onDeclineMembership!,
            ),
          if (row.membership == MembershipState.declined &&
              onReconsiderMembership != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onReconsiderMembership,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Reconsider'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The inline "a hub lists you" question (§5.6 step 4). Both answers are
/// always enabled — a disabled control would fail the contrast guideline
/// (handoff §2) and a question the user cannot answer is not a question.
class _MembershipPrompt extends StatelessWidget {
  const _MembershipPrompt({
    required this.title,
    required this.onConfirm,
    required this.onDecline,
  });

  final String title;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "'$title' lists you as a member. Show that you're a member "
            'of it?',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          // Wrap, not Row: on narrow screens the two labels + button padding
          // exceed the tile width, and buttons must never shrink or clip —
          // they wrap onto a second line instead.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(onPressed: onDecline, child: const Text('Not now')),
              FilledButton(
                onPressed: onConfirm,
                child: const Text('Show membership'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
