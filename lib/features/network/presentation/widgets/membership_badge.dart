/// Small state badges for a network row (presentation, libNetwork.md §5.1).
///
/// One widget, many optional chips: the tile composes it so every list, sheet
/// and (later) map pin shows the SAME badges with the SAME words. Plain-words
/// labels — the user never sees enum tokens or fetch internals.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// Renders the badges that apply to [row] (possibly none).
class MembershipBadge extends StatelessWidget {
  /// Creates the badge row for [row].
  const MembershipBadge(this.row, {super.key});

  /// The row to describe.
  final NetworkLibrary row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badges = <Widget>[
      // Hub→member direction: I added this library by scanning its card.
      if (row.isMember)
        _Chip(label: 'Member', color: scheme.primary, filled: true),
      if (row.isMember && row.memberVerified)
        _Chip(label: 'Verified', color: scheme.primary, filled: false),
      if (row.isMember && !row.memberVerified)
        // §5.7: a card added without a confirming fetch stays visibly
        // unverified — the in-person add is trusted, the network check is
        // pending, and the user can tell the two apart.
        _Chip(
          label: 'Unverified',
          color: scheme.onSurfaceVariant,
          filled: false,
        ),
      // Reciprocal consent (design 2026-10-18): a hub lists this library AND
      // the library's own site links back via memberOf — so viewers can tell
      // a claimed membership from a confirmed one.
      if (row.listedByHubUrl != null && row.confirmedByMember)
        _Chip(
          label: 'Confirmed by member',
          color: scheme.secondary,
          filled: false,
        ),
      // Member→hub direction: this hub lists me and I confirmed it.
      if (row.membership == MembershipState.confirmed)
        _Chip(label: 'My hub', color: scheme.tertiary, filled: false),
      // D12: a fetched identity contradicts the saved one — visible, never
      // auto-merged.
      if (row.fetchStatus == FetchStatus.identityConflict)
        _Chip(label: 'Identity conflict', color: scheme.error, filled: false),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.filled});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: filled ? Theme.of(context).colorScheme.onPrimary : color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
