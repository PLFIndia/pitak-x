/// A single library *grid* card (presentation layer, AGENTS.md §3.1).
///
/// The wide-screen counterpart to `BookRow`: a cover-forward card used by the
/// library grid on tablets/desktops. Same data and tap contract as the row, but
/// status markers (Removed / Not available / Needs info / copy-count) are shown
/// as small overlay pills on the cover so the title/author text below stays
/// uncluttered. Pure presentation — no business logic.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// One tappable book card for the wide-screen grid.
class BookGridCard extends StatelessWidget {
  /// Creates a card for [book]; [onTap] opens its detail.
  const BookGridCard({
    required this.book,
    required this.onTap,
    this.unavailable = false,
    super.key,
  });

  /// The book to render.
  final Book book;

  /// Called when the card is tapped.
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
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The cover absorbs all vertical slack so the text rows below have
            // a stable height — the card can never overflow its grid cell.
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox.expand(
                        // BookCover scales to fill the available cell width.
                        child: BookCover(
                          title: book.title,
                          coverUrl: book.coverUrl,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                  // Status pills overlaid on the cover's top edge. Wrap so any
                  // number of badges flow to a new line instead of overflowing.
                  Positioned(
                    top: 4,
                    left: 4,
                    right: 4,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (book.removed)
                          _Pill(
                            label: 'Removed',
                            background: scheme.errorContainer,
                            foreground: scheme.onErrorContainer,
                          ),
                        if (unavailable && !book.removed)
                          _Pill(
                            label: 'Not available',
                            background: scheme.secondaryContainer,
                            foreground: scheme.onSecondaryContainer,
                          ),
                        if (book.needsMetadata)
                          _Pill(
                            label: 'Needs info',
                            background: scheme.tertiaryContainer,
                            foreground: scheme.onTertiaryContainer,
                          ),
                        if (book.copyCount > 1)
                          _Pill(
                            label: '×${book.copyCount}',
                            background: scheme.primaryContainer,
                            foreground: scheme.onPrimaryContainer,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              style: textTheme.titleSmall?.copyWith(color: titleColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (book.author != null && book.author!.trim().isNotEmpty)
              Text(
                book.author!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Small pill badge overlaid on the cover for grid-card status markers.
class _Pill extends StatelessWidget {
  const _Pill({
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
