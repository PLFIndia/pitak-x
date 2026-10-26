/// Same-site poster image in the native public-events section.
///
/// The shared viewer pipeline downscales and caches the bytes in memory only.
/// Poster requests obey the same explicit remote-image consent as covers.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_event_poster_resolver.dart';
import 'package:pitaka/features/network/presentation/widgets/published_remote_image.dart';

/// Displays one published poster in a 3:4 slot, or its neutral placeholder.
class PublishedEventPosterImage extends StatelessWidget {
  /// Creates the poster image for [poster].
  const PublishedEventPosterImage({
    required this.poster,
    required this.siteUrl,
    this.requestsPaused = false,
    super.key,
  });

  /// The validated public poster metadata.
  final PublishedEventPoster poster;

  /// Saved site root used to resolve `posters/<leaf>`.
  final String siteUrl;

  /// Stops requests for an old snapshot during reload.
  final bool requestsPaused;

  @override
  Widget build(BuildContext context) => PublishedRemoteImage(
    request: PublishedEventPosterResolver.resolve(siteUrl, poster.imageRef),
    siteUrl: siteUrl,
    requestsPaused: requestsPaused,
    width: double.infinity,
    height: double.infinity,
    placeholderIcon: Icons.campaign_outlined,
  );
}
