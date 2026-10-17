/// Library network screen (presentation, AGENTS.md §3.1; libNetwork.md §5.1).
///
/// Two tabs:
///  - **Libraries** — every library you care about (migrated bookmarks, card
///    scans, discoveries), distance-sorted when this library publishes a pin
///    of its own, each row tappable to open its published site externally.
///    Refresh (button or pull) is the ONLY thing that reads other libraries'
///    descriptors — nothing happens in the background (D11). "Add member"
///    scans another library's card; the app-bar action adds a library by URL.
///  - **My card** — this library's own card QR for another library to scan
///    (§5.8). Exists only once the catalogue is published, because the card
///    IS the site URL plus a fingerprint fragment (D9).
///
/// The Map tab arrives with S5 — no "coming soon" placeholders in shipped UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/application/my_library_card_controller.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/add_member_page.dart';
import 'package:pitaka/features/network/presentation/widgets/add_library_dialog.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/network_refresh_bar.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// The library-network screen.
class NetworkPage extends ConsumerWidget {
  /// Creates the page.
  const NetworkPage({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library network'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: 'Add by URL',
              onPressed: () => _addByUrl(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Libraries'),
              Tab(text: 'My card'),
            ],
          ),
        ),
        body: const TabBarView(children: [_LibrariesTab(), _MyCardTab()]),
      ),
    );
  }
}

/// Display order for the Libraries tab (§7 S4): when this library publishes
/// a pin of its own (settings GPS × sharing — the D7 mapping, never a device
/// location), rows with coordinates sort nearest-first and pin-less rows
/// follow by name; without an own pin, everything sorts by name. The title
/// falls back to the URL so the order is always total and deterministic.
List<NetworkLibrary> sortRowsForDisplay(
  List<NetworkLibrary> rows,
  GeoPoint? own,
) {
  String titleOf(NetworkLibrary row) =>
      (row.name.isEmpty ? row.siteUrl : row.name).toLowerCase();
  int byTitle(NetworkLibrary a, NetworkLibrary b) =>
      titleOf(a).compareTo(titleOf(b));
  if (own == null) return [...rows]..sort(byTitle);
  final pinned = [...rows.where((row) => row.location != null)]
    ..sort((a, b) {
      final byDistance = own
          .distanceKm(a.location!)
          .compareTo(own.distanceKm(b.location!));
      if (byDistance != 0) return byDistance;
      // Tie-break on the title: List.sort is not stable, and the list must
      // not shuffle between builds when two pins are equally far away.
      return byTitle(a, b);
    });
  final unpinned = [...rows.where((row) => row.location == null)]
    ..sort(byTitle);
  return [...pinned, ...unpinned];
}

/// The saved-libraries list.
class _LibrariesTab extends ConsumerWidget {
  const _LibrariesTab();

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final added = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => const AddMemberPage()),
    );
    // Re-read the rows when a member was added (one truth: the repository).
    if (added ?? false) ref.invalidate(networkControllerProvider);
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
    final window = ref.watch(networkControllerProvider);
    // The own pin for distance sorting = the location THIS library publishes
    // (D7 mapping in one place; off/unparseable ⇒ no own pin ⇒ name order).
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final own = settings == null
        ? null
        : BuildOwnDescriptor.ownLocation(
            sharing: settings.publishLocationSharing,
            gps: settings.publishContactGps,
          );
    return Scaffold(
      body: window.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) =>
            const Center(child: Text("Couldn't load your saved libraries.")),
        data: (data) {
          final rows = sortRowsForDisplay(data.rows, own);
          return RefreshIndicator(
            // Pull-to-refresh runs the same single user-initiated refresh
            // (D11); the indicator settles when the run finishes or cancels.
            onRefresh: () =>
                ref.read(networkRefreshControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                const _InfoNote(),
                const SizedBox(height: 12),
                NetworkRefreshBar(window: data),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No libraries saved yet.\n\nAdd a library by its web '
                        'address (top right), or add a member by scanning '
                        'their library card, in person.',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMember(context, ref),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add member'),
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
