/// Empty-state for the library list (presentation layer).
///
/// S9/L3 distinguishes a genuinely empty library from an empty RESULT caused
/// by search text or kind/language facets. The first-run state offers Add /
/// Import; a filtered-empty state instead offers independent recovery actions
/// so the user never mistakes a filter for having no catalogue rows.
library;

import 'package:flutter/material.dart';

/// Centered placeholder shown when the list has no rows.
class EmptyLibraryState extends StatelessWidget {
  /// Creates the empty state. [hasQuery] and [hasFilters] describe the active
  /// read intent, not whether any rows happen to be stored. Recovery callbacks
  /// clear only their own part of that intent.
  const EmptyLibraryState({
    required this.hasQuery,
    required this.hasFilters,
    this.onClearSearch,
    this.onClearFilters,
    this.onAdd,
    this.onImport,
    super.key,
  });

  /// Whether non-blank search text is active.
  final bool hasQuery;

  /// Whether a kind or language facet is active.
  final bool hasFilters;

  /// Clears only the search text, preserving kind/language facets.
  final VoidCallback? onClearSearch;

  /// Clears only kind/language facets, preserving search text.
  final VoidCallback? onClearFilters;

  /// Opens the add-a-book flow (genuinely empty-library variant only).
  final VoidCallback? onAdd;

  /// Opens the import flow (genuinely empty-library variant only).
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isFiltered = hasQuery || hasFilters;
    final headline = isFiltered
        ? 'No items match these filters.'
        : 'Your library is empty';
    final hint = isFiltered
        ? 'Adjust or clear the active filters to see your items.'
        : 'Items you add will appear here.';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(headline, style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 20),
            // Wrap keeps the independent actions reachable on narrow screens
            // and at large text scales. Both appear when both intents apply.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (hasQuery && onClearSearch != null)
                  OutlinedButton(
                    onPressed: onClearSearch,
                    child: const Text('Clear search'),
                  ),
                if (hasFilters && onClearFilters != null)
                  OutlinedButton(
                    onPressed: onClearFilters,
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ] else if (onAdd != null || onImport != null) ...[
            const SizedBox(height: 20),
            // Add / Import belong ONLY to a genuinely empty unfiltered
            // library; they must not imply that a facet deleted the rows.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (onAdd != null)
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a book'),
                  ),
                if (onImport != null)
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
