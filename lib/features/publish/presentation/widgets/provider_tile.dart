/// Collapsible hosting-provider tiles of the publish Connection tab (S35).
///
/// Moved verbatim out of `publish_page.dart` (render-only presentation,
/// AGENTS §7) so the page stays a thin renderer: these widgets are pure
/// presentation with no state of their own beyond the tile's
/// expand/collapse.
library;

import 'package:flutter/material.dart';

/// A provider's configuration state shown in its tile header (S35, D3).
/// The text label is the primary carrier (accessibility); colour + icon
/// reinforce at a glance. Shades follow the existing brightness-aware green
/// pattern: ~400 on dark surfaces, ~700+ on light for contrast.
enum ProviderConfig {
  /// Signed in AND target repo set — ready to publish.
  configured('Configured', Icons.check_circle),

  /// Signed in, but no target repo yet.
  partial('Partially configured', Icons.warning_amber_rounded),

  /// A manual Cloudflare address still needs exact-origin verification.
  addressNotConfirmed('Address not confirmed yet', Icons.warning_amber_rounded),

  /// Confirmed target, but no deployment/read-back has proved write access.
  readyToPublish('Ready to publish', Icons.check_circle_outline),

  /// Not signed in / nothing set up.
  notConfigured('Not configured', Icons.cancel);

  const ProviderConfig(this.label, this.icon);

  /// The user-facing label (primary carrier of the state).
  final String label;

  /// The status icon.
  final IconData icon;

  /// The brightness-aware status colour.
  Color color(Brightness brightness) => switch (this) {
    ProviderConfig.configured =>
      brightness == Brightness.dark
          ? Colors.green.shade400
          : Colors.green.shade700,
    ProviderConfig.partial || ProviderConfig.addressNotConfirmed =>
      brightness == Brightness.dark
          ? Colors.amber.shade300
          : Colors.amber.shade800,
    ProviderConfig.readyToPublish =>
      brightness == Brightness.dark
          ? Colors.lightBlue.shade300
          : Colors.blue.shade700,
    ProviderConfig.notConfigured =>
      brightness == Brightness.dark ? Colors.red.shade300 : Colors.red.shade700,
  };
}

/// A collapsible provider card (S35): header = provider name + status
/// badge, body = that provider's settings. Matches the publish page's
/// section-card visuals so the tab reads as one family; collapsing is what
/// keeps the whole page on one screen. The default rotating chevron stays
/// as the expand affordance.
class ProviderTile extends StatelessWidget {
  /// Creates the tile.
  const ProviderTile({
    required this.title,
    required this.status,
    required this.body,
    this.subtitle,
    this.initiallyExpanded = false,
    super.key,
  });

  /// Provider name (tile header).
  final String title;

  /// Header status badge (D3).
  final ProviderConfig status;

  /// Optional second header line (e.g. "Coming soon").
  final String? subtitle;

  /// The settings shown when expanded.
  final Widget body;

  /// Whether the tile starts open (D4: the GitHub tile passes its latch).
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.color(theme.brightness);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        // N12 (320px / large text): both the title and the status label
        // ellipsize; icon and chevron keep their shape.
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(status.icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body],
      ),
    );
  }
}
