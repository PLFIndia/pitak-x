/// The subscription-status pill of a magazine title (periodicals
/// presentation layer, AGENTS.md §3.1; ADR 0013 D5, U2).
///
/// One widget for the Magazines list row AND the series detail page, so the
/// two can never disagree about wording or colours. The text comes from
/// `SubscriptionStatus.badgeLabel` (the domain owns the words); an untracked
/// subscription has no label and renders nothing.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';

/// A small pill showing where a title's subscription stands.
class SubscriptionBadge extends StatelessWidget {
  /// Creates a badge for [status]. Renders nothing for
  /// [SubscriptionStatus.untracked] (no badge, not an empty pill).
  const SubscriptionBadge({required this.status, super.key});

  /// The derived subscription state to show.
  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final label = status.badgeLabel;
    if (label == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Colour by severity, mirroring the catalogue row badges
    // (catalogue_item_row.dart): the calm states keep the soft container
    // tones; only "Lapsed" — the one that asks for action — uses the error
    // tones, the same rule "Removed" follows.
    final (background, foreground) = switch (status) {
      // Unreachable (untracked returned above) but kept so the switch is
      // exhaustive and a future status cannot fall through silently.
      SubscriptionStatus.untracked => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      SubscriptionStatus.active => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      SubscriptionStatus.expiringSoon => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      SubscriptionStatus.lapsed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
