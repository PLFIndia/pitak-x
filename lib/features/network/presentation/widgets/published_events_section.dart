/// Native Announcements & Events section for a saved library.
///
/// The optional events load never blocks or replaces the catalogue. Missing
/// `events.json` (including older published sites) renders nothing; a real
/// failure gets a small retryable message, unless a saved copy exists: then
/// the saved events are shown with a one-line note saying how old they are
/// (ADR 0018). Posters remain read-only and use the same consent-gated
/// memory-only image session as book covers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_events_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_messages.dart';
import 'package:pitaka/features/network/presentation/widgets/published_event_poster_image.dart';

/// Loads and displays public events for [siteUrl].
class PublishedEventsSection extends ConsumerWidget {
  /// Creates the section. [coverRequestsPaused] also pauses poster requests
  /// while the catalogue half of a reload still shows its previous snapshot.
  const PublishedEventsSection({
    required this.siteUrl,
    this.coverRequestsPaused = false,
    super.key,
  });

  /// Canonical saved site root.
  final String siteUrl;

  /// Whether images from the previous catalogue snapshot must stay paused.
  final bool coverRequestsPaused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(publishedEventsControllerProvider(siteUrl));
    final content = state.valueOrNull;
    final events = content?.value;
    final savedCopy = content?.savedCopy;
    if (events == null) {
      if (state.hasError) return _EventsError(siteUrl: siteUrl);
      // Initial loading and a normal 404 are intentionally quiet. Most older
      // sites have no events file, so a spinner/empty label would be noise.
      return const SizedBox.shrink();
    }
    if (events.posters.isEmpty && !events.hasPartialRead) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final paused = coverRequestsPaused || state.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text('Announcements & Events', style: textTheme.titleMedium),
        if (savedCopy != null) ...[
          const SizedBox(height: 4),
          Text(savedCopyMessage(savedCopy), style: textTheme.bodySmall),
        ],
        if (events.hasNewerSchema || events.hasPartialRead) ...[
          const SizedBox(height: 4),
          Text(
            'Some event details couldn’t be displayed.',
            style: textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        for (final poster in events.posters) ...[
          _PosterCard(poster: poster, siteUrl: siteUrl, requestsPaused: paused),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.poster,
    required this.siteUrl,
    required this.requestsPaused,
  });

  final PublishedEventPoster poster;
  final String siteUrl;
  final bool requestsPaused;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hasCaption = poster.description.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: PublishedEventPosterImage(
              poster: poster,
              siteUrl: siteUrl,
              requestsPaused: requestsPaused,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              hasCaption ? poster.description : 'No description',
              style: textTheme.bodyMedium?.copyWith(
                color: hasCaption ? scheme.onSurface : scheme.onSurfaceVariant,
                fontStyle: hasCaption ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventsError extends ConsumerWidget {
  const _EventsError({required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Couldn’t load announcements and events.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () => ref
                .read(publishedEventsControllerProvider(siteUrl).notifier)
                .refresh(),
            child: const Text('Retry events'),
          ),
        ],
      ),
    );
  }
}
