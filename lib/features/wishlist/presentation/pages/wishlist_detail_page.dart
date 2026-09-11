/// Wishlist entry detail (presentation layer, AGENTS.md §3.1).
///
/// Read-only field rows plus actions: edit, mark-purchased, delete. The
/// mutating actions go through [WishlistController] (which runs the use cases
/// and refreshes the list).
///
/// **Observes the entry by id (N03).** Pushed with a `bookId` (plus,
/// optionally, the tapped row for the first frame) and watching
/// `wishlistBookByIdProvider(bookId)` from then on, so a row rewritten while
/// this page is open (edit saved, purchased elsewhere, cover materialised) is
/// shown in place and Edit always opens on the CURRENT row. Delete and
/// purchase still pop — the entry is gone or the user's task is complete —
/// but Edit no longer has to pop to escape a stale snapshot. A vanished row
/// shows a safe empty state; a read failure a safe message.
///
/// Purchase actions (M13): both buttons are disabled while a purchase is in
/// flight (no double-tap), and a failed purchase keeps the user ON this page
/// with a plain-language message so they can retry — the use case rolled the
/// write back, so the entry is still "Wanted" and the buttons stay visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';

/// Displays the wishlist entry with id [bookId], kept current, with edit /
/// purchase / delete actions.
class WishlistDetailPage extends ConsumerWidget {
  /// Creates the detail page for the entry with [bookId]. [initialBook] is
  /// the tapped list row, shown only until the observed row arrives.
  const WishlistDetailPage({required this.bookId, this.initialBook, super.key});

  /// Id of the entry to observe.
  final int bookId;

  /// Optional snapshot for the first frame; never handed to any action.
  final WishlistBook? initialBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observed = ref.watch(wishlistBookByIdProvider(bookId));
    // `valueOrNull` keeps the previous value during a reload (no loading
    // flash); `hasValue` separates "resolved to null" from "not yet".
    if (observed.hasValue) {
      final book = observed.valueOrNull;
      if (book == null) return const _EntryGoneScaffold();
      return _WishlistDetailBody(book: book);
    }
    if (observed.hasError) return const _EntryLoadFailedScaffold();
    final first = initialBook;
    if (first != null && first.id == bookId) {
      return _WishlistDetailBody(book: first);
    }
    return const Scaffold(
      appBar: _DetailAppBar(),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// The plain app bar shared by the loading / gone / failed states.
class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Wishlist item'));
}

/// Shown when the observed row no longer exists. No actions.
class _EntryGoneScaffold extends StatelessWidget {
  const _EntryGoneScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This entry is no longer on your wishlist.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Shown when the row could not be read (repo AGENTS.md §5: safe words only).
class _EntryLoadFailedScaffold extends StatelessWidget {
  const _EntryLoadFailedScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't load this entry. Please go back and try again.",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.error),
          ),
        ),
      ),
    );
  }
}

/// The detail screen proper, rendered for the CURRENT [book]. Stateful only
/// for the purchase busy flag (M13).
class _WishlistDetailBody extends ConsumerStatefulWidget {
  const _WishlistDetailBody({required this.book});

  final WishlistBook book;

  @override
  ConsumerState<_WishlistDetailBody> createState() =>
      _WishlistDetailBodyState();
}

class _WishlistDetailBodyState extends ConsumerState<_WishlistDetailBody> {
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
            // N03: the form gets the CURRENT row and re-reads it at save;
            // when it pops, this page already observes the edited row.
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddWishlistPage(book: book),
              ),
            ),
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
