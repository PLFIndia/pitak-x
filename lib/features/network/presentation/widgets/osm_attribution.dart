/// The OpenStreetMap attribution (presentation, libNetwork.md §5.9).
///
/// The OSM tile-usage policy REQUIRES visible credit wherever the tiles are
/// shown. This uses flutter_map's [RichAttributionWidget]: a permanently
/// visible toggle button (bottom-right by default) that opens a popup with
/// the full "© OpenStreetMap contributors" credit. The compact form matters
/// on narrow phones — the plain [SimpleAttributionWidget] renders its whole
/// text inline and can overflow small viewports. Tapping the credit opens
/// the copyright page in the external browser — the same rule as every
/// external link in the app (validated https, never an in-app webview).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// The permanently-visible OSM credit toggle, bottom-right on the map.
class OsmAttribution extends StatelessWidget {
  /// Creates the attribution widget.
  const OsmAttribution({super.key});

  /// The OSM copyright page the credit links to (a UI-link concern, so it
  /// lives here — presentation must not import the tile-provider
  /// infrastructure file).
  static final Uri copyrightUri = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      attributions: [
        TextSourceAttribution(
          'OpenStreetMap contributors',
          onTap: () =>
              launchUrl(copyrightUri, mode: LaunchMode.externalApplication),
        ),
      ],
    );
  }
}
