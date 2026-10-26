/// One saved library in the network list (presentation, docs/ARCHITECTURE.md §3 network).
///
/// Deliberately thin: name (or the URL when a row has no name yet), the site
/// address, the shared [MembershipBadge] row, and a tap callback owned by the
/// screen. Since ADR 0015 the normal tap opens the library's published
/// catalogue INSIDE Pitak (a native, read-only page); the tile itself no
/// longer touches HTTP or the browser, so opening a row can never launch an
/// external app by accident. The viewer's explicit "Open in browser" action is
/// the only external hand-off (and `NetworkMapPage`'s sheet keeps its own).
///
/// The member→hub prompt (§5.6 step 4) lives HERE, inline under its row:
/// a `pending` row asks "show that you're a member?" with plain Confirm /
/// No buttons, and a `declined` row keeps a quiet "Reconsider" action —
/// the user is never re-prompted automatically, but the door stays open.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';

/// A list tile for one [NetworkLibrary] row.
class NetworkLibraryTile extends StatelessWidget {
  /// Creates the tile. [onOpen] null renders no normal tap action (previews
  /// and goldens); the membership callbacks null hide the prompt/Reconsider
  /// actions; [onRemove] null hides remove.
  const NetworkLibraryTile({
    required this.row,
    this.onOpen,
    this.onRemove,
    this.onConfirmMembership,
    this.onDeclineMembership,
    this.onReconsiderMembership,
    super.key,
  });

  /// The row to render.
  final NetworkLibrary row;

  /// Called when the user taps the row: the screen opens the native
  /// published-catalogue viewer. Never launches the browser.
  final VoidCallback? onOpen;

  /// Called when the user asks to remove the row.
  final VoidCallback? onRemove;

  /// Called when the user answers the pending-membership prompt "yes".
  final VoidCallback? onConfirmMembership;

  /// Called when the user answers the pending-membership prompt "no".
  /// Declining is permanent (never re-prompted) but reversible: the row
  /// keeps a quiet "Reconsider" action. There is deliberately no "not
  /// now" snooze — leaving the prompt unanswered IS the snooze (review
  /// Lows: a soft label must not hide a permanent decision).
  final VoidCallback? onDeclineMembership;

  /// Called when the user taps "Reconsider" on a declined membership.
  final VoidCallback? onReconsiderMembership;

  /// Display title: the name when known, else the site URL.
  String get title => row.name.isEmpty ? row.siteUrl : row.name;

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
            onTap: onOpen,
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
              TextButton(onPressed: onDecline, child: const Text('No')),
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
