/// The Cloudflare provider tile of the publish Connection tab (S35, D1).
///
/// Moved out of `provider_tile.dart` (Cloudflare plan S0/E.4: one file per
/// provider tile, extracted before the real Direct-Upload-to-Worker
/// integration lands).
///
/// Copy rule (S0): the old body advised the user to connect the GitHub repo to
/// "Cloudflare Pages" in the Cloudflare dashboard. That is withdrawn — a
/// dashboard Git integration is an explicit non-goal, and Pages is not the
/// target product (Workers static assets are). The tile now states only what
/// is true today: this app cannot publish to Cloudflare yet.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

/// The Cloudflare tile: always "Not configured" + "Coming soon" until the
/// Direct-Upload integration lands. Collapsed by default (D4 applies to GitHub
/// only — auto-expanding an unimplemented provider would defeat the
/// one-screen goal).
class CloudflareTile extends StatelessWidget {
  /// Creates the Cloudflare placeholder tile.
  const CloudflareTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderTile(
      title: 'Cloudflare Workers',
      subtitle: 'Coming soon',
      status: ProviderConfig.notConfigured,
      body: Text(
        'Publishing your catalogue straight to Cloudflare from this app is '
        'not available yet. When it ships it will use your own Cloudflare '
        'account and a Worker dedicated to Pitak. Until then there is '
        'nothing to set up here.',
      ),
    );
  }
}
