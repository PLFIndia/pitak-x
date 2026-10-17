/// Library network screen (presentation, AGENTS.md §3.1; libNetwork.md §5.1).
///
/// Two tabs:
///  - **Libraries** — every library you care about (migrated bookmarks, card
///    scans, later: discoveries), each row tappable to open its published
///    site externally. The "Add member" action scans another library's card.
///  - **My card** — this library's own card QR for another library to scan
///    (§5.8). Exists only once the catalogue is published, because the card
///    IS the site URL plus a fingerprint fragment (D9).
///
/// The Map tab arrives with S5 — no "coming soon" placeholders in shipped UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/network/application/my_library_card_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/add_member_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';

/// The library-network screen.
class NetworkPage extends ConsumerWidget {
  /// Creates the page.
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library network'),
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

/// The saved-libraries list.
class _LibrariesTab extends ConsumerWidget {
  const _LibrariesTab();

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final added = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => const AddMemberPage()),
    );
    // Re-read the rows when a member was added (one truth: the repository).
    if (added ?? false) ref.invalidate(networkRowsProvider);
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    NetworkLibrary row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = await ref.read(networkRepositoryProvider.future);
    final result = await repo.removeById(row.id);
    result.match(
      (_) => messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't remove that library.")),
      ),
      (_) {
        ref.invalidate(networkRowsProvider);
        messenger.showSnackBar(const SnackBar(content: Text('Removed.')));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(networkRowsProvider);
    return Scaffold(
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) =>
            const Center(child: Text("Couldn't load your saved libraries.")),
        data: (rows) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const _InfoNote(),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No libraries saved yet.\n\nAdd a member by scanning '
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
                ),
          ],
        ),
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
              'Libraries you save appear here. A hub adds members by '
              'scanning their library card in person; tapping a library '
              'opens its published catalogue in your browser.',
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
