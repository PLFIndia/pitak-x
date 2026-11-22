/// The Library list's error state (presentation layer, AGENTS.md §3.1).
///
/// Moved out of `library_page.dart` in November 2026 (review finding P4-M2)
/// to keep that page under the 500-line cap.
library;

import 'package:flutter/material.dart';

/// Safe error state — never shows raw exception text (AGENTS.md §5).
class LibraryErrorState extends StatelessWidget {
  /// Creates the error state. [isSearching] chooses the sentence; [onRetry]
  /// is null while the list is already being read again.
  const LibraryErrorState({
    required this.isSearching,
    required this.onRetry,
    super.key,
  });

  /// Whether the read that failed was a search (there is text in the box).
  final bool isSearching;

  /// Reads the list again; null while that is already happening, which
  /// greys the button out.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = isSearching
        ? "Couldn't run that search. Please try again."
        : "Couldn't load your library. Please try again.";
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
