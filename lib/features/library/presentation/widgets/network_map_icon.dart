import 'package:flutter/material.dart';

/// Network-map destination icon: a filled map plus a location pin.
///
/// Colour reinforces the map meaning, while the silhouette and the parent
/// IconButton's "Network map" tooltip keep it understandable without colour.
class NetworkMapIcon extends StatelessWidget {
  /// Creates the icon using the current theme's primary and tertiary colours.
  const NetworkMapIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.map_rounded, color: scheme.primary),
        Positioned(
          right: -4,
          bottom: -3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Icon(Icons.location_on, size: 14, color: scheme.tertiary),
            ),
          ),
        ),
      ],
    );
  }
}
