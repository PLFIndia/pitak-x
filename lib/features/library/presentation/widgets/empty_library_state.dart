/// Empty-state for the library list (presentation layer).
///
/// Parity with Kotlin `LibraryScreen.EmptyLibraryState` + the D17 onboarding
/// card: a "no matches" variant while searching, and a first-run "library is
/// empty" state otherwise with Add / Import actions so it is never a dead-end
/// (Kotlin D26). The decorative animated welcome splash is intentionally not
/// ported (§3a — branding gold-plating, no functional value).
library;

import 'package:flutter/material.dart';

/// Centered placeholder shown when the list has no rows.
class EmptyLibraryState extends StatelessWidget {
  /// Creates the empty state. [isSearching] picks the "no matches" copy and
  /// [query] is echoed back to the user. On the first-run (non-searching)
  /// variant, [onAdd] / [onImport] surface action buttons when provided.
  const EmptyLibraryState({
    required this.isSearching,
    required this.query,
    this.onAdd,
    this.onImport,
    super.key,
  });

  /// Whether the empty list is the result of an active search.
  final bool isSearching;

  /// The current query text (echoed in the "no matches" message).
  final String query;

  /// Opens the add-a-book flow (first-run variant only).
  final VoidCallback? onAdd;

  /// Opens the import flow (first-run variant only).
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final headline = isSearching
        ? 'No matches for "${query.trim()}"'
        : 'Your library is empty';
    final hint = isSearching
        ? 'Try a different title, author, or ISBN.'
        : 'Books you add will appear here.';

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
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!isSearching && (onAdd != null || onImport != null)) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onAdd != null)
                  FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a book'),
                  ),
                if (onAdd != null && onImport != null)
                  const SizedBox(width: 12),
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
