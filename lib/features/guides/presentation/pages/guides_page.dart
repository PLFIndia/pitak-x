/// "How Pitak works" index (presentation, AGENTS.md §3.1).
///
/// An intro line and one card per guide in the catalog; tapping a card opens
/// that guide as its own page (not an accordion — an open accordion pushes
/// the other topics off-screen, and a page gets a back button plus the
/// deep-link button at the bottom). Render-only, no providers.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/domain/guide_catalog.dart';
import 'package:pitaka/features/guides/presentation/pages/guide_page.dart';

/// The guides index page.
class GuidesPage extends StatelessWidget {
  /// Creates the index.
  const GuidesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('How Pitak works')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Short guides, one per job. Each ends with a button to the right '
            'screen.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final guide in guideCatalog) ...[
            _GuideCard(guide),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// One index card: icon, title, one-line subtitle, chevron.
class _GuideCard extends StatelessWidget {
  const _GuideCard(this.guide);

  final Guide guide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(_iconFor(guide.id), color: scheme.primary),
        title: Text(
          guide.title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          guide.cardSubtitle,
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => GuidePage(guide: guide)),
        ),
      ),
    );
  }

  /// Icons are Flutter, so they live here (presentation), keyed by the pure
  /// [GuideId] — never stored in the domain model.
  static IconData _iconFor(GuideId id) => switch (id) {
    GuideId.catalogue => Icons.library_books_outlined,
    GuideId.publish => Icons.cloud_upload_outlined,
    GuideId.map => Icons.place_outlined,
    GuideId.backup => Icons.save_outlined,
    GuideId.vault => Icons.lock_outline,
    GuideId.network => Icons.hub_outlined,
  };
}
