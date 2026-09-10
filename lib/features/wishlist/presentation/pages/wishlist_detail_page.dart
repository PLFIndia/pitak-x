/// Wishlist entry detail (presentation layer, AGENTS.md §3.1).
///
/// Read-only field rows plus actions: edit, mark-purchased, delete. The
/// mutating actions go through [WishlistController] (which runs the use cases
/// and refreshes the list); on success this view pops back to the refreshed
/// list rather than show a stale snapshot.
///
/// Purchase actions (M13): both buttons are disabled while a purchase is in
/// flight (no double-tap), and a failed purchase keeps the user ON this page
/// with a plain-language message so they can retry — the use case rolled the
/// write back, so the entry is still "Wanted" and the buttons stay visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';

/// Displays a single wishlist entry with edit / purchase / delete actions.
class WishlistDetailPage extends ConsumerStatefulWidget {
  /// Creates the detail page for [book].
  const WishlistDetailPage({required this.book, super.key});

  /// The entry to display.
  final WishlistBook book;

  @override
  ConsumerState<WishlistDetailPage> createState() => _WishlistDetailPageState();
}

class _WishlistDetailPageState extends ConsumerState<WishlistDetailPage> {
  /// True while a purchase is being written. Owned by this State so the two
  /// purchase buttons share one guard (a `ConsumerWidget` has nowhere to keep
  /// it). Pattern borrowed from `_DeleteForeverButtonState` in
  /// `book_detail_page.dart`.
  bool _purchasing = false;

  WishlistBook get book => widget.book;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Future<void> popToList() async {
      if (context.mounted) Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlist item'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddWishlistPage(book: book),
                ),
              );
              await popToList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove from wishlist?'),
                  content: const Text('This entry will be deleted.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed ?? false) {
                await ref
                    .read(wishlistControllerProvider.notifier)
                    .delete(book.id);
                await popToList();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(book.title, style: textTheme.headlineSmall),
          if (_has(book.author)) ...[
            const SizedBox(height: 4),
            Text(book.author!, style: textTheme.titleMedium),
          ],
          const SizedBox(height: 24),
          _DetailRow(label: 'ISBN', value: book.isbn),
          _DetailRow(label: 'Publisher', value: book.publisher),
          _DetailRow(label: 'Published', value: book.publishedYear?.toString()),
          _DetailRow(label: 'Priority', value: _priorityLabel(book.priority)),
          _DetailRow(
            label: 'Price estimate',
            value: book.priceEstimate?.toString(),
          ),
          _DetailRow(
            label: 'Status',
            value: book.purchased ? 'Purchased' : 'Wanted',
          ),
          if (_has(book.notes)) ...[
            const SizedBox(height: 16),
            Text(
              'Notes',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(book.notes!, style: textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          if (!book.purchased) ...[
            FilledButton.icon(
              icon: const Icon(Icons.library_add),
              label: const Text('Purchased — add to library'),
              onPressed: _purchasing
                  ? null
                  : () => _markPurchased(moveToLibrary: true),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Mark as purchased only'),
              onPressed: _purchasing ? null : _markPurchased,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markPurchased({bool moveToLibrary = false}) async {
    setState(() => _purchasing = true);
    final result = await ref
        .read(wishlistControllerProvider.notifier)
        .markPurchased(book.id, moveToLibrary: moveToLibrary);
    if (!mounted) return;
    setState(() => _purchasing = false);

    result.match(
      // M13: the use case rolled back, the entry is unchanged — stay here so
      // the user can retry, and say what happened in safe words.
      (failure) => _snack(_purchaseFailureMessage(failure)),
      (outcome) {
        switch (outcome) {
          case MarkPurchasedSuccess():
            break;
          case MarkPurchasedAlreadyInLibrary():
            // D2: the entry is still purchased; just tell the user.
            _snack('Marked purchased. It was already in your library.');
          case MarkPurchasedAlreadyPurchased():
            _snack('This entry was already marked purchased.');
        }
        // The list behind us has been refreshed; this snapshot is stale.
        Navigator.of(context).pop();
      },
    );
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Plain-language, non-leaking text for a purchase [failure] (repo AGENTS.md
  /// §5: never show raw exception text).
  static String _purchaseFailureMessage(Failure failure) => switch (failure) {
    NotFoundFailure() => 'This entry no longer exists. Nothing was changed.',
    ValidationFailure(:final message) => message,
    _ => 'Could not save the purchase. Nothing was changed — please try again.',
  };

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  static String _priorityLabel(int p) => switch (p) {
    WishlistBook.priorityHigh => 'High',
    WishlistBook.priorityLow => 'Low',
    _ => 'Medium',
  };
}

/// One label/value row; renders nothing when [value] is null/blank.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
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
