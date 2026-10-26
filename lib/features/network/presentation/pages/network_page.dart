/// Library network screen (presentation, AGENTS.md §3.1; docs/ARCHITECTURE.md §3 network).
///
/// Three tabs:
///  - **Libraries** — every library you care about (migrated bookmarks, card
///    scans, discoveries), distance-sorted when this library publishes a pin
///    of its own. Tapping a row opens that library's published catalogue in a
///    native, read-only page (ADR 0015); the browser is only reached from the
///    viewer's explicit "Open in browser" action. Refresh (button or pull) is
///    the ONLY thing that reads other libraries' descriptors — nothing happens
///    in the background (D11). "Add member" scans another library's card in
///    person; adding by URL lives on the standalone Library Bookmarks page.
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
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/add_member_page.dart';
import 'package:pitaka/features/network/presentation/pages/network_map_page.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/saved_libraries_view.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';

/// The library-network screen.
class NetworkPage extends ConsumerWidget {
  /// Creates the page. [initialTab] selects the opening tab — the home
  /// screen's map button lands straight on the Map tab (1).
  /// [publishedSiteOpener] is the viewer's injectable browser seam (tests
  /// record launches).
  const NetworkPage({
    super.key,
    this.initialTab = 0,
    this.publishedSiteOpener = const PublishedSiteOpener(),
  });

  /// The tab to open on (0 = Libraries, 1 = Map, 2 = My card).
  final int initialTab;

  /// The browser hand-off seam forwarded to the published-catalogue viewer.
  final PublishedSiteOpener publishedSiteOpener;

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
        body: TabBarView(
          children: [
            _LibrariesTab(opener: publishedSiteOpener),
            const NetworkMapGate(),
            const _MyCardTab(),
          ],
        ),
      ),
    );
  }
}

/// The network tab keeps the shared list and only the in-person add action.
class _LibrariesTab extends StatelessWidget {
  const _LibrariesTab({required this.opener});

  /// The browser seam forwarded to the viewer route.
  final PublishedSiteOpener opener;

  /// AddMemberController refreshes the shared window after a member is saved,
  /// so there is nothing to patch in the list when this route returns.
  Future<void> _addMember(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const AddMemberPage()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SavedLibrariesView(
        opener: opener,
        emptyStateHint:
            'Tap "Add member" to scan a library card in person. Use Library '
            'Bookmarks in the main drawer to save a library by its web '
            'address.',
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'networkAddMember',
        onPressed: () => _addMember(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add member'),
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
