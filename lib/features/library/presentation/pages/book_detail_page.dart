/// Read-only book detail screen (presentation layer).
///
/// Parity with Kotlin `BookDetailScreen`: title + transliteration + author
/// header, a "Removed" badge, then the labeled detail rows in the same order
/// (ISBN, publisher, published, genre, language, pages, shelf, quantity,
/// source, source detail, age group, added date, added by) and a notes block.
/// Edit + Remove/Restore actions.
///
/// **Observes the book by id (N03).** The page is pushed with a `bookId` (and,
/// optionally, the list row's `Book` so the first frame is not a spinner) and
/// watches `bookByIdProvider(bookId)` from then on. Everything that can change
/// the row while this page is open — a cover captured right here, the
/// remote-cover materializer, the edit form — signals through the library
/// controller, and this page re-reads the row on that signal. So a new cover
/// appears in place, Edit always opens on the CURRENT row, and there is no
/// stale snapshot left to write back. A row that vanished shows a safe empty
/// state; a repository failure shows a safe message, never raw text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/library/application/book_cover_controller.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/presentation/pages/add_book_page.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';

/// A portrait 2:3 crop preset — the natural shape of a book cover. The plugin's
/// built-in enum only offers landscape ratios (e.g. 3:2), so we supply this
/// custom preset; `data` is (ratioX, ratioY) and is passed straight to the
/// native cropper.
class _Ratio2x3Preset implements CropAspectRatioPresetData {
  const _Ratio2x3Preset();

  @override
  String get name => '2x3';

  @override
  (int, int)? get data => (2, 3);
}

/// Crop ratio presets offered for a book cover. Replaces the default landscape
/// 3:2 with a portrait 2:3 (the realistic cover shape); free-form + square +
/// original remain available.
const List<CropAspectRatioPresetData> _coverCropPresets = [
  CropAspectRatioPreset.original,
  CropAspectRatioPreset.square,
  _Ratio2x3Preset(),
];

/// Initial ratio shown when the cropper opens. Must be one of
/// [_coverCropPresets]; also required for the custom list to apply on Android.
const CropAspectRatioPresetData _coverInitPreset = _Ratio2x3Preset();

/// Displays the book with id [bookId], kept current, with Edit and
/// Remove/Restore actions.
class BookDetailPage extends ConsumerWidget {
  /// Creates the detail page for the book with [bookId]. [initialBook] is the
  /// row the caller already has (the tapped list row); it is shown only until
  /// the observed row arrives, so the first frame is not a spinner.
  const BookDetailPage({required this.bookId, this.initialBook, super.key});

  /// Per-device id of the book to observe.
  final int bookId;

  /// Optional snapshot for the first frame; never used once the provider has
  /// resolved, and never handed to any action.
  final Book? initialBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observed = ref.watch(bookByIdProvider(bookId));
    // `valueOrNull` keeps the previous value during a reload, so a rewritten
    // row swaps in without a loading flash; `hasValue` distinguishes "resolved
    // to null" (the row is gone) from "not resolved yet".
    if (observed.hasValue) {
      final book = observed.valueOrNull;
      if (book == null) return const _BookGoneScaffold();
      return _BookDetailBody(book: book);
    }
    if (observed.hasError) return const _BookLoadFailedScaffold();
    final first = initialBook;
    if (first != null && first.id == bookId) {
      return _BookDetailBody(book: first);
    }
    return const Scaffold(
      appBar: _DetailAppBar(),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// The plain "Book" app bar shared by the loading / gone / failed states.
class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Book'));
}

/// Shown when the observed row no longer exists (deleted from another screen
/// or device while this page was open). No actions: there is nothing to
/// edit, remove or lend.
class _BookGoneScaffold extends StatelessWidget {
  const _BookGoneScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This book is no longer in your library.',
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

/// Shown when the row could not be read. Plain-language only (repo AGENTS.md
/// §5: never raw exception text).
class _BookLoadFailedScaffold extends StatelessWidget {
  const _BookLoadFailedScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't load this book. Please go back and try again.",
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

/// The detail screen proper, rendered for the CURRENT [book]. Every action
/// here uses this observed row — the edit form, the cover pipeline and the
/// janitor all see fresh values.
class _BookDetailBody extends ConsumerWidget {
  const _BookDetailBody({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
    final vaultUnlocked = session is VaultUnlocked;
    // Same rule the lend use case enforces; evaluated here only to render an
    // honest button state + reason (review 2026-09-03, decision Q4).
    final lendDecision = session is VaultUnlocked
        ? LendDecision.forBook(book, session.data.loans)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            // The edit form gets the CURRENT row and re-reads it again at
            // save time. When it pops, this page is already observing the
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
          // Lend action (vault unlocked). Disabled — with the reason shown —
          // when the lending policy would refuse (removed / all copies out).
          if (vaultUnlocked && lendDecision != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: lendDecision is LendAllowed
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LendBookPage(
                          bookId: book.id,
                          bookTitle: book.title,
                        ),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.outbox),
              label: const Text('Lend'),
            ),
            if (lendDecision.reason != null) ...[
              const SizedBox(height: 6),
              Text(
                lendDecision.reason!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
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
  /// unset (addedDate == 0 means "no date recorded"). M15: an out-of-range
  /// value from a pre-M15 row renders as no date instead of throwing.
  static String? _formatDate(int epochMillis) {
    final d = CatalogueRules.dateFromMillisOrNull(epochMillis)?.toLocal();
    if (d == null) return null;
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

/// Book cover with a camera-capture "replace" affordance (#cover).
///
/// The widget owns only the plugin steps (camera capture + crop); the raw
/// bytes then go to `BookCoverController`, which downscales, stores, and
/// persists them (§7). The capture stays entirely on-device.
///
/// N03: the cover shown is the OBSERVED row's `coverUrl` — this widget keeps
/// no copy of its own. `replaceCover` invalidates the library, the page
/// re-reads the row, and the new image arrives through `widget.book`. The
/// controller also receives the observed row, so the janitor releases the
/// reference the row really held (a second capture in one visit used to
/// release the ORIGINAL snapshot's file and leave the intermediate one).
class _EditableCover extends ConsumerStatefulWidget {
  const _EditableCover({required this.book});

  final Book book;

  @override
  ConsumerState<_EditableCover> createState() => _EditableCoverState();
}

class _EditableCoverState extends ConsumerState<_EditableCover> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      // Suppress the app lock for the camera + crop activities: each launches a
      // separate OS activity that backgrounds us, which would otherwise trip
      // the biometric gate mid-capture.
      final suppressor = ref.read(lockSuppressorProvider.notifier);
      final shot = await suppressor.guard(
        () => ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 90,
        ),
      );
      if (shot == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      // Free-crop step: let the user frame the cover. A null result means the
      // user cancelled the crop — abort the whole capture (nothing is saved).
      final cropped = await suppressor.guard(
        () => ImageCropper().cropImage(
          sourcePath: shot.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop cover',
              lockAspectRatio: false,
              aspectRatioPresets: _coverCropPresets,
              // REQUIRED on Android: uCrop only applies a custom preset list
              // when an initial ratio is also given; without this the list is
              // ignored and the default (landscape) presets show instead.
              initAspectRatio: _coverInitPreset,
            ),
            IOSUiSettings(
              title: 'Crop cover',
              aspectRatioPresets: _coverCropPresets,
            ),
          ],
        ),
      );
      if (cropped == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final raw = await cropped.readAsBytes();
      // The testable pipeline (downscale → store → persist → refresh) lives
      // in the application layer (§7 "no business logic in widgets"); the
      // widget only owns the plugin calls above and renders the outcome.
      final result = await ref
          .read(bookCoverControllerProvider.notifier)
          .replaceCover(widget.book, raw);
      if (!mounted) return;
      result.match(
        (_) => _snack('Could not save the new cover.'),
        // The row is rewritten and the library signalled; the observed book
        // above us re-renders with the new reference — nothing to keep here.
        (_) => _snack('Cover updated.'),
      );
    } on Exception {
      // Plugin (camera/crop) failure only — pipeline errors are typed above.
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
          key: ValueKey(widget.book.coverUrl),
          title: widget.book.title,
          coverUrl: widget.book.coverUrl,
          bookId: widget.book.id,
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
