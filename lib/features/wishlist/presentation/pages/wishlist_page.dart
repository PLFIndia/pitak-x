/// Wishlist list screen (presentation layer, AGENTS.md §3.1).
///
/// Lists active entries first, then purchased ones (each section newest-first).
/// FAB adds; tapping a row opens its detail. Pure presentation: reads
/// [WishlistController] and forwards user intent to it. Sort/filter facets and
/// cover images are deferred (PLAN Step 14 out-of-scope).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/presentation/pages/add_wishlist_page.dart';
import 'package:pitaka/features/wishlist/presentation/pages/wishlist_detail_page.dart';
import 'package:pitaka/features/wishlist/presentation/widgets/wishlist_row.dart';

/// The wishlist list screen.
class WishlistPage extends ConsumerWidget {
  /// Creates the wishlist page.
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wishlistControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddWishlistPage()),
        ),
        tooltip: 'Add to wishlist',
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load your wishlist."),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(wishlistControllerProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (books) => books.isEmpty
            ? const _EmptyWishlist()
            : _WishlistList(books: books),
      ),
    );
  }
}

class _WishlistList extends StatelessWidget {
  const _WishlistList({required this.books});

  final List<WishlistBook> books;

  @override
  Widget build(BuildContext context) {
    // Active first, then purchased; each preserves the controller's order.
    final active = books.where((b) => !b.purchased).toList();
    final purchased = books.where((b) => b.purchased).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final b in active) _row(context, b),
        if (purchased.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Purchased'),
          ),
          for (final b in purchased) _row(context, b),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, WishlistBook book) => WishlistRow(
    book: book,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WishlistDetailPage(book: book)),
    ),
  );
}

class _EmptyWishlist extends StatelessWidget {
  const _EmptyWishlist();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          const Text('Your wishlist is empty'),
          const SizedBox(height: 8),
          Text(
            'Books you want to buy will appear here.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
