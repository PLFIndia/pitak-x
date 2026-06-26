/// A single wishlist list row (presentation layer).
///
/// Shows title + author, a priority badge (High/Low; Medium is the unmarked
/// default), and a "Purchased" badge for bought entries. Cover image is
/// deferred (no image dep this slice).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// One tappable wishlist row.
class WishlistRow extends StatelessWidget {
  /// Creates a row for [book]; [onTap] opens its detail.
  const WishlistRow({required this.book, required this.onTap, super.key});

  /// The entry to render.
  final WishlistBook book;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dimmed = book.purchased;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.titleMedium?.copyWith(
          color: dimmed ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      subtitle: (book.author != null && book.author!.trim().isNotEmpty)
          ? Text(book.author!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book.purchased)
            _Badge(
              label: 'Purchased',
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
            )
          else
            ?_priorityBadge(scheme),
        ],
      ),
    );
  }

  Widget? _priorityBadge(ColorScheme scheme) {
    return switch (book.priority) {
      WishlistBook.priorityHigh => _Badge(
        label: 'High',
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
      WishlistBook.priorityLow => _Badge(
        label: 'Low',
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
      _ => null, // Medium (default) shows no badge.
    };
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
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
