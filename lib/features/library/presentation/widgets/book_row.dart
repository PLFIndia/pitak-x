/// A single library list row (presentation layer).
///
/// Parity with Kotlin `LibraryScreen.BookRow`: title (2 lines), author, and the
/// status badges — removed (dimmed + badge), needs-metadata, copy-count "×N",
/// and the vault "Not available" badge (every copy is out on loan, shown only
/// when the vault is unlocked so availability is known).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// One tappable book row.
class BookRow extends StatelessWidget {
  /// Creates a row for [book]; [onTap] opens its detail.
  const BookRow({
    required this.book,
    required this.onTap,
    this.unavailable = false,
    super.key,
  });

  /// The book to render.
  final Book book;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  /// True when every copy is out on loan (vault unlocked). Shows a badge.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Removed books are dimmed (visible-but-inert), mirroring Kotlin D39.
    final titleColor = book.removed
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            BookCover(title: book.title, coverUrl: book.coverUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: textTheme.titleMedium?.copyWith(color: titleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null && book.author!.trim().isNotEmpty)
                    Text(
                      book.author!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Trailing status markers. Constrained + wrapping so several badges
            // (or large text scales) flow onto a second line instead of
            // overflowing the row off-screen.
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (book.removed)
                    _Badge(
                      label: 'Removed',
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                    ),
                  if (unavailable && !book.removed)
                    _Badge(
                      label: 'Not available',
                      background: scheme.secondaryContainer,
                      foreground: scheme.onSecondaryContainer,
                    ),
                  if (book.needsMetadata)
                    _Badge(
                      label: 'Needs info',
                      background: scheme.tertiaryContainer,
                      foreground: scheme.onTertiaryContainer,
                    ),
                  if (book.copyCount > 1)
                    Text(
                      '×${book.copyCount}',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill badge used for row status markers.
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
    // Spacing between badges is handled by the parent Wrap; no inner margin.
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
