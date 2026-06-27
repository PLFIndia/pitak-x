/// Read-only book detail screen (presentation layer).
///
/// Parity with Kotlin `BookDetailScreen`: title + transliteration + author
/// header, a "Removed" badge, then the labeled detail rows in the same order
/// (ISBN, publisher, published, genre, language, pages, shelf, quantity,
/// source, source detail, age group, added date, added by) and a notes block.
/// Shows the book it is handed, with Edit + Remove/Restore actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';

/// Displays a single [Book]'s fields with Edit and Remove/Restore actions.
class BookDetailPage extends ConsumerWidget {
  /// Creates the detail page for [book].
  const BookDetailPage({required this.book, super.key});

  /// The book to display.
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final vaultUnlocked =
        ref.watch(vaultSessionControllerProvider).valueOrNull is VaultUnlocked;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddBookPage(book: book),
                ),
              );
              // The edit screen refreshes the library list on save. This
              // detail view holds the pre-edit snapshot, so return to the
              // (refreshed) list rather than show stale fields.
              if (context.mounted) Navigator.of(context).pop();
            },
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
              onPressed: () async {
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
                  await ref
                      .read(libraryControllerProvider.notifier)
                      .remove(book.id);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _EditableCover(book: book)),
          const SizedBox(height: 16),
          Text(book.title, style: textTheme.headlineSmall),
          if (_has(book.titleTransliteration)) ...[
            const SizedBox(height: 4),
            Text(
              book.titleTransliteration!,
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_has(book.author)) ...[
            const SizedBox(height: 4),
            Text(book.author!, style: textTheme.titleMedium),
          ],
          if (book.removed) ...[
            const SizedBox(height: 12),
            _RemovedBadge(scheme: scheme, textTheme: textTheme),
          ],
          // Lend action (vault unlocked; not offered for removed books).
          if (vaultUnlocked && !book.removed) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LendBookPage(bookId: book.id, bookTitle: book.title),
                ),
              ),
              icon: const Icon(Icons.outbox),
              label: const Text('Lend'),
            ),
          ],
          const SizedBox(height: 24),
          // Labeled rows in the exact order of the Kotlin detail screen.
          _DetailRow(label: 'ISBN', value: book.isbn),
          _DetailRow(label: 'Publisher', value: book.publisher),
          _DetailRow(label: 'Published', value: book.publishedYear?.toString()),
          _DetailRow(label: 'Genre', value: book.genre),
          _DetailRow(label: 'Language', value: book.language),
          _DetailRow(label: 'Pages', value: book.pageCount?.toString()),
          _DetailRow(label: 'Shelf location', value: book.location),
          _DetailRow(label: 'Quantity', value: book.copyCount.toString()),
          _DetailRow(label: 'Source', value: _sourceLabel(book.sourceType)),
          _DetailRow(label: 'Source detail', value: book.sourceDetail),
          _DetailRow(label: 'Age group', value: _ageGroupLabel(book.ageGroup)),
          _DetailRow(label: 'Added', value: _formatDate(book.addedDate)),
          _DetailRow(label: 'Added by', value: book.addedBy),
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
          const SizedBox(height: 32),
          _DeleteForeverButton(book: book),
        ],
      ),
    );
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// Human label for the acquisition source enum (null/`other` handled).
  static String? _sourceLabel(BookSourceType? type) {
    return switch (type) {
      null => null,
      BookSourceType.purchased => 'Purchased',
      BookSourceType.gift => 'Gift',
      BookSourceType.donated => 'Donated',
      BookSourceType.inherited => 'Inherited',
      BookSourceType.other => 'Other',
    };
  }

  /// Human label for the reader age band.
  static String? _ageGroupLabel(AgeGroup? group) {
    return switch (group) {
      null => null,
      AgeGroup.above3 => 'Ages 3+',
      AgeGroup.above6 => 'Ages 6+',
      AgeGroup.above10 => 'Ages 10+',
      AgeGroup.above15 => 'Ages 15+',
      AgeGroup.advanced => 'Advanced',
    };
  }

  /// Formats an epoch-millis added date as a plain `YYYY-MM-DD`, or null when
  /// unset (addedDate == 0 means "no date recorded").
  static String? _formatDate(int epochMillis) {
    if (epochMillis <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

/// Book cover with a camera-capture "replace" affordance (#cover).
///
/// Tapping the camera button captures a photo (camera only), downscales it to
/// 400x600 JPEG q80 ([ImageDownscaler]), writes it to `covers/<uuid>.jpg`
/// (CoverStore), updates the book row, and refreshes the library. The capture
/// stays entirely on-device.
class _EditableCover extends ConsumerStatefulWidget {
  const _EditableCover({required this.book});

  final Book book;

  @override
  ConsumerState<_EditableCover> createState() => _EditableCoverState();
}

class _EditableCoverState extends ConsumerState<_EditableCover> {
  bool _busy = false;
  String? _coverUrl;

  @override
  void initState() {
    super.initState();
    _coverUrl = widget.book.coverUrl;
  }

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (shot == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      // Free-crop step: let the user frame the cover. A null result means the
      // user cancelled the crop — abort the whole capture (nothing is saved).
      final cropped = await ImageCropper().cropImage(
        sourcePath: shot.path,
        uiSettings: [
          AndroidUiSettings(toolbarTitle: 'Crop cover', lockAspectRatio: false),
          IOSUiSettings(title: 'Crop cover'),
        ],
      );
      if (cropped == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final raw = await cropped.readAsBytes();
      final jpeg = ImageDownscaler.downscaleJpeg(raw);
      if (jpeg == null) {
        _snack('That image could not be processed.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      final store = await ref.read(coverStoreProvider.future);
      final ref0 = await store.saveJpeg(jpeg);
      final repo = await ref.read(bookRepositoryProvider.future);
      final result = await repo.update(widget.book.copyWith(coverUrl: ref0));
      if (!mounted) return;
      result.match((_) => _snack('Could not save the new cover.'), (_) {
        ref.invalidate(libraryControllerProvider);
        setState(() => _coverUrl = ref0);
        _snack('Cover updated.');
      });
    } on Exception {
      _snack('Could not capture a photo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BookCover(
          // Key on the cover ref so a new capture forces an image reload.
          key: ValueKey(_coverUrl),
          title: widget.book.title,
          coverUrl: _coverUrl,
          width: 120,
          height: 168,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _capture,
          icon: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_camera_outlined),
          label: const Text('Replace cover'),
        ),
      ],
    );
  }
}

/// One label/value row. Renders nothing when [value] is null/blank.
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

class _RemovedBadge extends StatelessWidget {
  const _RemovedBadge({required this.scheme, required this.textTheme});

  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          'Removed',
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

/// "Delete permanently" action (#27/D3). A hard delete must purge the book's
/// vault loans, so it routes through [DeleteBookUseCase]: if the vault is
/// locked it asks the user to unlock first (we never delete while we can't
/// confirm/purge loans — fail-closed, no vault-state leak).
class _DeleteForeverButton extends ConsumerStatefulWidget {
  const _DeleteForeverButton({required this.book});

  final Book book;

  @override
  ConsumerState<_DeleteForeverButton> createState() =>
      _DeleteForeverButtonState();
}

class _DeleteForeverButtonState extends ConsumerState<_DeleteForeverButton> {
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
    final useCase = await ref.read(deleteBookUseCaseProvider.future);
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
