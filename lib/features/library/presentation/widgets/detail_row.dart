/// One label/value row of a detail screen (presentation layer).
///
/// Extracted from `catalogue_item_detail_page.dart` in S17 so the page's
/// labelled rows and the kind-specific `ItemDetailsSection` share the one
/// layout (AGENTS §0 "one blessed way"). Pure view: renders nothing when the
/// value is null/blank, so callers can list rows unconditionally.
library;

import 'package:flutter/material.dart';

/// One label/value row. Renders nothing when [value] is null/blank.
class DetailRow extends StatelessWidget {
  /// Creates the row for [label] showing [value].
  const DetailRow({required this.label, required this.value, super.key});

  /// The row's label (e.g. 'ISBN').
  final String label;

  /// The value to show; null or blank renders nothing.
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value!, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
