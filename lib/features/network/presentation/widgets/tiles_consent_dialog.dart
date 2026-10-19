/// The one-time OpenStreetMap tiles consent dialog (presentation,
/// docs/ARCHITECTURE.md §1 network egress).
///
/// The map needs raster tiles from `tile.openstreetmap.org`, and fetching
/// them tells the OSM servers the device IP and the area being viewed. That
/// is a NEW third-party egress, so it is opt-in: the map never builds until
/// the user accepts here (the acceptance is persisted as
/// `AppSettings.networkMapTilesConsent`). Plain words, no legalese; Decline
/// simply means "stay with the list".
library;

import 'package:flutter/material.dart';

/// Asks whether the map may download OpenStreetMap tiles.
///
/// Returns `true` on Accept, `false` on Decline or dismiss — fail closed:
/// anything but an explicit tap on Accept means "no consent".
class TilesConsentDialog extends StatelessWidget {
  /// Creates the dialog.
  const TilesConsentDialog({super.key});

  /// Shows the dialog and resolves to the user's choice (see class doc).
  static Future<bool> ask(BuildContext context) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (_) => const TilesConsentDialog(),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Show the network map?'),
      content: const Text(
        'The map picture comes from OpenStreetMap. While the map is open, '
        'your device downloads map images from their servers — they see '
        'your internet address and the area you are looking at, like any '
        'website you visit.\n\n'
        'Your list of libraries never leaves the device. You can change '
        'this later in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No thanks'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Show the map'),
        ),
      ],
    );
  }
}
