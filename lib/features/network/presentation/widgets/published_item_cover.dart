/// Read-only cover placeholder for a published item (network presentation;
/// viewer plan S4/S5).
///
/// Until S5 wires the consent-gated, memory-only cover pipeline, EVERY item
/// shows this placeholder. The widget deliberately never receives a network
/// URL in this build: no `Image.network`, no `Image.file`, and nothing written
/// to disk. That keeps the "viewing a catalogue downloads no images" promise
/// true even if the page is used before covers land.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// A bounded cover slot: the real downscaled image, or a neutral placeholder.
class PublishedItemCover extends StatelessWidget {
  /// Creates the cover slot for [item] of the library saved at [siteUrl].
  const PublishedItemCover({
    required this.item,
    required this.siteUrl,
    this.width = 44,
    this.height = 64,
    super.key,
  });

  /// The item whose cover is shown (kept for the S5 resolver key).
  final PublishedCatalogueItem item;

  /// The saved site root (the relative-cover resolution base).
  final String siteUrl;

  /// Slot width.
  final double width;

  /// Slot height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.menu_book_outlined,
          size: width * 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
