/// Library network screen (presentation, AGENTS.md §3.1; libNetwork.md §5.1).
///
/// Three tabs:
///  - **Libraries** — every library you care about (migrated bookmarks, card
///    scans, discoveries), distance-sorted when this library publishes a pin
///    of its own, each row tappable to open its published site externally.
///    Refresh (button or pull) is the ONLY thing that reads other libraries'
///    descriptors — nothing happens in the background (D11). Two buttons sit
///    bottom-right: "Add bookmark" saves a library by its web address, and
///    "Add member" scans another library's card in person.
///  - **Map** — the saved libraries as pins (§5.9). Gated behind the OSM
///    tiles consent: no tile request ever leaves the device until the user
///    accepts. The map body lives in `network_map_page.dart`.
///  - **My card** — this library's own card QR for another library to scan
///    (§5.8). Exists only once the catalogue is published, because the card
///    IS the site URL plus a fingerprint fragment (D9).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/network/application/my_library_card_controller.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/add_member_page.dart';
import 'package:pitaka/features/network/presentation/pages/network_map_page.dart';
import 'package:pitaka/features/network/presentation/widgets/add_library_dialog.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/network_refresh_bar.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';

/// The library-network screen.
class NetworkPage extends ConsumerWidget {
  /// Creates the page. [initialTab] selects the opening tab — the home
  /// screen's map button lands straight on the Map tab (1).
  const NetworkPage({super.key, this.initialTab = 0});

  /// The tab to open on (0 = Libraries, 1 = Map, 2 = My card).
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library network'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Libraries'),
              Tab(text: 'Map'),
              Tab(text: 'My card'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_LibrariesTab(), NetworkMapGate(), _MyCardTab()],
        ),
      ),
    );
  }
}

/// The saved-libraries list.
class _LibrariesTab extends ConsumerWidget {
  const _LibrariesTab();

  /// Opens the scan flow. Nothing to do on return: `AddMemberController`
  /// re-reads the window the moment a member is saved, so the list is fresh
  /// whether the user tapped Done or pressed back (review M10).
  Future<void> _addMember(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const AddMemberPage()));

  /// Saves a library by its web address (the "Add bookmark" button).
  Future<void> _addByUrl(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (_) => const AddLibraryDialog(),
    );
    if (result == null) return;
    final outcome = await ref
        .read(networkControllerProvider.notifier)
        .addByUrl(url: result.url, name: result.name);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          NetworkAddOutcome.added =>
            'Library added. Tap Refresh to fetch its details.',
          NetworkAddOutcome.alreadySaved => 'That library is already saved.',
          NetworkAddOutcome.invalidUrl =>
            'That link was not accepted. Use a GitHub Pages or Cloudflare '
                'Pages address.',
          NetworkAddOutcome.storageFailed => "Couldn't add that library.",
        }),
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
    // One snapshot: the window (for the refresh bar) plus the rows already
    // in display order — the sort lives in the derived provider, recomputed
    // when its inputs change, not on every build (review M12).
    final view = ref.watch(networkListViewProvider);
    return Scaffold(
      body: view.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) =>
            const Center(child: Text("Couldn't load your saved libraries.")),
        data: (data) {
          final rows = data.rows;
          return RefreshIndicator(
            // Pull-to-refresh runs the same single user-initiated refresh
            // (D11); the indicator settles when the run finishes or cancels.
            onRefresh: () =>
                ref.read(networkRefreshControllerProvider.notifier).refresh(),
            child: ListView(
              // Bottom padding clears the two stacked buttons (was 88 for
              // one FAB).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 150),
              children: [
                const _InfoNote(),
                const SizedBox(height: 12),
                NetworkRefreshBar(window: data.window),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No libraries saved yet.\n\nTap "Add bookmark" to '
                        'save a library by its web address, or "Add member" '
                        'to scan their library card, in person.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (final row in rows)
                    NetworkLibraryTile(
                      row: row,
                      onRemove: () => _remove(context, ref, row),
                      onConfirmMembership: () =>
                          _decide(context, ref, row, MembershipState.confirmed),
                      onDeclineMembership: () =>
                          _decide(context, ref, row, MembershipState.declined),
                      onReconsiderMembership: () =>
                          _decide(context, ref, row, MembershipState.pending),
                    ),
              ],
            ),
          );
        },
      ),
      // Two stacked actions: bookmark by URL, or scan a member's card. Each
      // needs its own heroTag — two extended FABs share the default one.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'networkAddBookmark',
            onPressed: () => _addByUrl(context, ref),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Add bookmark'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'networkAddMember',
            onPressed: () => _addMember(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Add member'),
          ),
        ],
      ),
    );
  }
}

/// Plain-words explainer of what this list is (and what leaves the device:
/// nothing until the user taps Refresh — D11).
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
              'library opens its published catalogue in your browser.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// This library's own card QR (§5.8).
class _MyCardTab extends ConsumerWidget {
  const _MyCardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLibraryCardControllerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) =>
          const Center(child: Text("Couldn't build your library card.")),
      data: (card) {
        if (card == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Your library card appears once you have published your '
                'catalogue (drawer → Publish to web). The card is how '
                'another library adds you as a member, in person.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final payload = LibraryCardPayload.encode(card);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your library card',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Another Pitak library scans this to add you as a member. A '
              'phone camera simply opens your published site — the card '
              'never contains your private library ID, only its public '
              'fingerprint.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Center(child: QrView(data: payload, size: 254)),
            const SizedBox(height: 16),
            SelectableText(
              card.siteUrl,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              // Reuses the visiting-card pipeline: the sheet renders the
              // same PNG card, now with the card payload as its QR data.
              onPressed: () =>
                  showShareLibrarySheet(context, url: card.siteUrl),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share as image'),
            ),
          ],
        );
      },
    );
  }
}
