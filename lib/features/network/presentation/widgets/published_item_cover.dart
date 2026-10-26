/// Read-only cover slot for a published item (network presentation; ADR 0015
/// V11). Resolution is cover-specific; consent, scheduling, memory caching and
/// rendering live in the shared [PublishedRemoteImage] used by event posters
/// too. Same-site and third-party covers both retain the remote-cover opt-in.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/presentation/widgets/published_remote_image.dart';

/// A bounded cover slot: the real downscaled image, or a neutral placeholder.
class PublishedItemCover extends StatelessWidget {
  /// Creates the cover slot for [item] of the library saved at [siteUrl].
  const PublishedItemCover({
    required this.item,
    required this.siteUrl,
    this.coverRequestsPaused = false,
    this.width = 44,
    this.height = 64,
    super.key,
  });

  /// The item whose cover is shown.
  final PublishedCatalogueItem item;

  /// The saved site root (the relative-cover resolution base).
  final String siteUrl;

  /// When true, never request a cover this frame.
  final bool coverRequestsPaused;

  /// Slot width.
  final double width;

  /// Slot height.
  final double height;

  @override
  Widget build(BuildContext context) => PublishedRemoteImage(
    request: PublishedCoverResolver.resolve(siteUrl, item.coverUrl),
    siteUrl: siteUrl,
    requestsPaused: coverRequestsPaused,
    width: width,
    height: height,
  );
}
