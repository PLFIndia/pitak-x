/// Collapsible hosting-provider tiles of the publish Connection tab (S35).
///
/// Moved verbatim out of `publish_page.dart` (render-only presentation,
/// AGENTS §7) so the page stays a thin renderer: these widgets are pure
/// presentation with no state of their own beyond the tile's
/// expand/collapse.
library;

import 'package:flutter/material.dart';

/// Brightness-aware status colours shared by the provider tiles (S35, D3;
/// review item 13).
///
/// The light shades are chosen against the ACTUAL light card colour
/// (`surfaceContainerLow` of the indigo-seeded scheme, not pure white) for
/// at least 4.5:1 — the small bold status labels count as small text under
/// WCAG. The dark shades are the long-standing ~300/400 tints, which sit far
/// above 4.5:1 on the dark card. `test/features/publish/
/// provider_status_contrast_test.dart` pins every pair in both themes.
abstract final class ProviderStatusColors {
  /// Success (configured / signed in / token verified).
  static Color success(Brightness brightness) => brightness == Brightness.dark
      ? Colors.green.shade400
      : Colors.green.shade800;

  /// Warning (partially configured / address not confirmed).
  static Color warning(Brightness brightness) => brightness == Brightness.dark
      ? Colors.amber.shade300
      : Colors.deepOrange.shade900;

  /// Informational (ready to publish, nothing proved yet).
  static Color info(Brightness brightness) => brightness == Brightness.dark
      ? Colors.lightBlue.shade300
      : Colors.blue.shade800;

  /// Error (not configured).
  static Color error(Brightness brightness) =>
      brightness == Brightness.dark ? Colors.red.shade300 : Colors.red.shade800;
}

/// A provider's configuration state shown in its tile header (S35, D3).
/// The text label is the primary carrier (accessibility); colour + icon
/// reinforce at a glance. Colours come from [ProviderStatusColors].
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
    ProviderConfig.configured => ProviderStatusColors.success(brightness),
    ProviderConfig.partial || ProviderConfig.addressNotConfirmed =>
      ProviderStatusColors.warning(brightness),
    ProviderConfig.readyToPublish => ProviderStatusColors.info(brightness),
    ProviderConfig.notConfigured => ProviderStatusColors.error(brightness),
  };
}

/// A collapsible provider card (S35): header = provider name with the status
/// badge on the line below it, body = that provider's settings. Matches the
/// publish page's section-card visuals so the tab reads as one family;
/// collapsing is what keeps the whole page on one screen. The default
/// rotating chevron stays as the expand affordance.
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
        // Name on the first line, status on the second. On one line the two
        // competed for a phone's width and BOTH were cut off ("Cloudflare
        // Wor…" + a clipped status, S11 smoke 2026-10-29). Stacked, each gets
        // the full width; N12 (320px / large text) is still covered because
        // each line wraps once and only then ellipsizes.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(status.icon, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    status.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
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
