/// The OpenStreetMap attribution (presentation, libNetwork.md §5.9).
///
/// The OSM tile-usage policy REQUIRES visible credit wherever the tiles are
/// shown — and says the credit must not be hidden behind toggles or links.
/// That rules out flutter_map's `RichAttributionWidget`: its default shows
/// only an "i" icon until tapped, and opening the credit on a timer (the
/// library's `popupInitialDisplayDuration`) is a bare `Future.delayed` that
/// leaks past widget disposal and ships a sub-48 dp close button (review
/// M3). So the full "© OpenStreetMap contributors" text here is on screen
/// from the FIRST FRAME, always, in a chip that stays readable over any
/// tile imagery.
///
/// Tapping the credit opens the copyright page in the external browser —
/// the same rule as every external link in the app (validated https, never
/// an in-app webview).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The always-visible OSM credit, bottom-right on the map.
class OsmAttribution extends StatelessWidget {
  /// Creates the attribution widget.
  const OsmAttribution({super.key});

  /// The OSM copyright page the credit links to.
  static final Uri copyrightUri = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // LayoutBuilder: as a FlutterMap child this widget receives the FULL map
    // size; the chip aligns itself bottom-right. On very narrow viewports
    // the text wraps to two lines instead of overflowing — the font size
    // never shrinks, because "clearly readable" is the policy's bar.
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(0, constraints.maxWidth - 16),
            ),
            child: Semantics(
              // The same proven pattern as the map pins: one labelled
              // Semantics node over a GestureDetector (an InkWell's focusable
              // gesture subtree merged into the map's label-less semantics
              // node and failed the a11y tap-label check).
              button: true,
              label: 'OpenStreetMap copyright',
              child: GestureDetector(
                onTap: () => launchUrl(
                  copyrightUri,
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  // No `alignment` here on purpose: an aligned Container
                  // expands to the loose max constraints (the whole map) and
                  // eats every tap. Symmetric padding makes the credit one
                  // ≥48 dp tap target (like the map pins) and shrink-wraps.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    // Opaque, not translucent: the a11y contrast check reads
                    // composited pixels, and map tiles are arbitrary imagery.
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '© OpenStreetMap contributors',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
