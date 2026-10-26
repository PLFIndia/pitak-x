/// Explicit remote-cover opt-in for the published-catalogue viewer.
///
/// The banner is deliberately separate from cover scheduling: it explains the
/// existing setting and forwards the user's tap, while `PublishedItemCover` and
/// its controller remain the fail-closed network gates (ADR 0015 V11).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Offers to enable published covers when a loaded catalogue needs them and
/// the app-wide remote-cover setting is known to be off.
class PublishedCoverConsentBanner extends ConsumerWidget {
  /// Creates the banner for an already-loaded [catalogue].
  const PublishedCoverConsentBanner({
    required this.catalogue,
    this.hasEventPosters = false,
    super.key,
  });

  /// The loaded catalogue whose cover references determine whether an opt-in
  /// prompt is useful.
  final PublishedCatalogue catalogue;

  /// Whether the independently-loaded events snapshot also has images waiting
  /// behind the same consent gate.
  final bool hasEventPosters;

  bool get _hasCoverReferences =>
      hasEventPosters ||
      catalogue.items.any((item) => item.coverUrl != null) ||
      catalogue.periodicals.any((series) => series.coverUrl != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hasCoverReferences) return const SizedBox.shrink();
    // valueOrNull deliberately keeps a previously-loaded OFF value visible if
    // a preference WRITE fails. The network gates still read OFF (fail closed),
    // and the user can retry; an initial settings failure has no value and
    // therefore keeps this prompt hidden.
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    if (settings == null || settings.loadRemoteCovers) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.image_outlined,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cover images are off. Load covers from this library '
                  "and Pitak's approved cover services? Event posters "
                  'come only from this library. In this viewer, images '
                  'stay in memory and disappear when you leave.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref
                      .read(settingsControllerProvider.notifier)
                      .setLoadRemoteCovers(enabled: true),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Load covers'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
