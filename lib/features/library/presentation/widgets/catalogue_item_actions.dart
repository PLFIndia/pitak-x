/// The detail page's action widgets (presentation layer, AGENTS.md §3.1).
///
/// Extracted from `catalogue_item_detail_page.dart` (plan S14) so the page
/// drops back under the 500-line cap — the kind-specific detail sections of
/// S17 will need that room. Everything here acts on the CURRENT observed
/// [CatalogueItem] the page hands down (N03): no widget keeps a snapshot of
/// its own.
///
/// What lives here:
/// - [CatalogueItemActions]: the app-bar actions — Edit, Remove/Restore with
///   its confirmation dialog;
/// - [LendSection]: the lend button with its enabled/disabled reason, or the
///   locked/uninitialized hint routing to the vault screen;
/// - [DeleteForeverButton]: the hard-delete action with its vault rule.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/delete_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

/// App-bar actions for the detail page: Edit always, then Remove or Restore
/// depending on the row's soft-delete flag.
class CatalogueItemActions extends ConsumerWidget {
  /// Creates the actions for the CURRENT [book] (the observed row).
  const CatalogueItemActions({required this.book, super.key});

  /// The observed row the actions act on.
  final CatalogueItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Edit',
          // The edit form gets the CURRENT row and re-reads it again at
          // save time. When it pops, the page is already observing the
          // edited row, so there is nothing stale to escape from.
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => AddBookPage(book: book)),
          ),
        ),
        if (book.removed)
          IconButton(
            icon: const Icon(Icons.restore_from_trash),
            tooltip: 'Restore to library',
            onPressed: () async {
              await ref
                  .read(libraryControllerProvider.notifier)
                  .restoreRemoved(book.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          )
        else
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove from library',
            onPressed: () => _confirmRemove(context, ref),
          ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: const Text(
          'The book stays in your records but is marked removed. '
          'You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await ref.read(libraryControllerProvider.notifier).remove(book.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// The lend action with its honest button state (S34, decision Q4): rendered
/// whenever the vault state is KNOWN, so a locked vault explains itself
/// instead of silently hiding the feature.
///
/// - unlocked → the lending policy decides enabled/disabled + reason;
/// - locked / uninitialized → a disabled button plus a hint that routes to
///   the vault screen. The page above WATCHES the session, so after
///   unlocking and popping back it rebuilds with a live button;
/// - still loading / errored → nothing at all (a transient state); the
///   caller handles that case by not rendering this widget.
class LendSection extends StatelessWidget {
  /// Creates the section for [book] under the resolved [session].
  const LendSection({required this.book, required this.session, super.key});

  /// The observed row a loan would be taken out on.
  final CatalogueItem book;

  /// The current vault session (already resolved by the caller).
  final VaultSessionState session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final session = this.session;

    if (session is VaultUnlocked) {
      // Same rule the lend use case enforces; evaluated here only to render
      // an honest button state + reason — the use case stays the gate.
      final decision = LendDecision.forItem(book, session.data.loans);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: decision is LendAllowed
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LendBookPage(bookId: book.id, bookTitle: book.title),
                    ),
                  )
                : null,
            icon: const Icon(Icons.outbox),
            label: const Text('Lend'),
          ),
          if (decision.reason != null) ...[
            const SizedBox(height: 6),
            Text(
              decision.reason!,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    // Locked or uninitialized: disabled (grayed by the theme) — lending needs
    // an unlocked vault and there is no bypass (fail closed).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.outbox),
          label: const Text('Lend'),
        ),
        const SizedBox(height: 6),
        Text(
          session is VaultLocked
              ? 'Unlock the borrowers vault to lend this book.'
              : 'Set up the borrowers vault to start lending.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const VaultPage())),
          icon: Icon(
            session is VaultLocked ? Icons.lock_open : Icons.lock_outline,
            size: 18,
          ),
          label: Text(
            session is VaultLocked ? 'Unlock the vault' : 'Set up the vault',
          ),
        ),
      ],
    );
  }
}

/// "Delete permanently" action (#27/D3). A hard delete must purge the book's
/// vault loans, so it routes through [DeleteCatalogueItemUseCase]: if the vault
/// is locked it asks the user to unlock first (we never delete while we can't
/// confirm/purge loans — fail-closed, no vault-state leak).
class DeleteForeverButton extends ConsumerStatefulWidget {
  /// Creates the button for the CURRENT [book].
  const DeleteForeverButton({required this.book, super.key});

  /// The observed row to delete.
  final CatalogueItem book;

  @override
  ConsumerState<DeleteForeverButton> createState() =>
      _DeleteForeverButtonState();
}

class _DeleteForeverButtonState extends ConsumerState<DeleteForeverButton> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'This removes the book for good, along with any of its lending '
          'records in the vault. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final useCase = await ref.read(deleteCatalogueItemUseCaseProvider.future);
    final result = await useCase(widget.book.id);
    if (!mounted) return;
    setState(() => _busy = false);

    result.match((_) => _snack('Could not delete this book.'), (outcome) {
      switch (outcome) {
        case DeleteBookOutcome.deleted:
          ref.invalidate(libraryControllerProvider);
          Navigator.of(context).pop();
        case DeleteBookOutcome.requiresVaultUnlock:
          _snack('Unlock the borrowers vault first, then try deleting again.');
      }
    });
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: _busy ? null : _delete,
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.delete_forever, color: scheme.error),
      label: Text('Delete permanently', style: TextStyle(color: scheme.error)),
    );
  }
}
