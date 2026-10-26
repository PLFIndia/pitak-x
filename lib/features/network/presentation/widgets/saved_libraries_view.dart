/// Shared saved-libraries list for the network tab and Library Bookmarks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/network_refresh_bar.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';

/// Shows saved libraries with refresh, removal, and membership actions.
///
/// The host screen owns add actions and supplies [emptyStateHint]. Keeping that
/// hint outside the shared list prevents the empty state from naming a button
/// that is not present on the current screen.
class SavedLibrariesView extends ConsumerWidget {
  /// Creates the shared list.
  const SavedLibrariesView({
    required this.emptyStateHint,
    this.opener = const PublishedSiteOpener(),
    super.key,
  });

  /// The browser hand-off seam forwarded to the native catalogue viewer.
  final PublishedSiteOpener opener;

  /// Screen-specific guidance shown below the shared empty-list heading.
  final String emptyStateHint;

  /// Opens the native viewer; a normal row tap never leaves the app (ADR 0015).
  void _openRow(BuildContext context, NetworkLibrary row) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PublishedCataloguePage(row: row, opener: opener),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    NetworkLibrary row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(networkControllerProvider.notifier).remove(row);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Removed.' : "Couldn't remove that library."),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    NetworkLibrary row,
    MembershipState decision,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(networkControllerProvider.notifier)
        .setMembership(rowId: row.id, decision: decision);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save that choice.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The derived provider supplies one consistent snapshot and keeps sorting
    // out of the widget build method.
    final view = ref.watch(networkListViewProvider);
    return view.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) =>
          const Center(child: Text("Couldn't load your saved libraries.")),
      data: (data) {
        final rows = data.rows;
        return RefreshIndicator(
          // Pull-to-refresh and the Refresh button run the same explicitly
          // user-initiated controller action; nothing refreshes in background.
          onRefresh: () =>
              ref.read(networkRefreshControllerProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const _InfoNote(),
                    const SizedBox(height: 12),
                    NetworkRefreshBar(window: data.window),
                  ]),
                ),
              ),
              if (rows.isEmpty)
                SliverPadding(
                  // Leave room for the host screen's single extended FAB.
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No libraries saved yet.\n\n$emptyStateHint',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                  // Build rows lazily so large saved networks stay inexpensive.
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      return NetworkLibraryTile(
                        row: row,
                        onOpen: () => _openRow(context, row),
                        onRemove: () => _remove(context, ref, row),
                        onConfirmMembership: () => _decide(
                          context,
                          ref,
                          row,
                          MembershipState.confirmed,
                        ),
                        onDeclineMembership: () => _decide(
                          context,
                          ref,
                          row,
                          MembershipState.declined,
                        ),
                        onReconsiderMembership: () =>
                            _decide(context, ref, row, MembershipState.pending),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Explains what the shared list contains and when network traffic occurs.
class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Libraries you save appear here. Nothing leaves your device '
              "until you tap Refresh, which reads each library's published "
              'details (name, optional map pin, hub links). A hub adds '
              'members by scanning their library card in person; tapping a '
              'library opens its published catalogue inside Pitak.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
