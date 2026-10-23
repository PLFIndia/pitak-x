/// Read-only book detail screen (presentation layer).
///
/// Parity with Kotlin `BookDetailScreen`: title + transliteration + author
/// header, a "Removed" badge, then the labeled detail rows in the same order
/// (ISBN, publisher, published, genre, language, pages, shelf, quantity,
/// source, source detail, age group, added date, added by) and a notes block.
/// Edit + Remove/Restore actions.
///
/// **Observes the book by id (N03).** The page is pushed with a `bookId` (and,
/// optionally, the list row's `CatalogueItem` so the first frame is not a
/// spinner) and watches `catalogueItemByIdProvider(bookId)` from then on.
/// Everything that can change the row while this page is open — a cover
/// captured right here, the remote-cover materializer, the edit form — signals
/// through the library controller, and this page re-reads the row on that
/// signal. So a new cover appears in place, Edit always opens on the CURRENT
/// row, and there is no stale snapshot left to write back. A row that vanished
/// shows a safe empty state; a repository failure shows a safe message, never
/// raw text.
///
/// S14: the app-bar actions, the lend section and the delete-forever button
/// live in `widgets/catalogue_item_actions.dart` (the page grew over the
/// file-size cap; the split makes room for S17's kind-specific sections).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/cover_crop.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/library/application/book_cover_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_actions.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// Displays the book with id [bookId], kept current, with Edit and
/// Remove/Restore actions.
class CatalogueItemDetailPage extends ConsumerWidget {
  /// Creates the detail page for the book with [bookId]. [initialBook] is the
  /// row the caller already has (the tapped list row); it is shown only until
  /// the observed row arrives, so the first frame is not a spinner.
  const CatalogueItemDetailPage({
    required this.bookId,
    this.initialBook,
    super.key,
  });

  /// Per-device id of the book to observe.
  final int bookId;

  /// Optional snapshot for the first frame; never used once the provider has
  /// resolved, and never handed to any action.
  final CatalogueItem? initialBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observed = ref.watch(catalogueItemByIdProvider(bookId));
    // `valueOrNull` keeps the previous value during a reload, so a rewritten
    // row swaps in without a loading flash; `hasValue` distinguishes "resolved
    // to null" (the row is gone) from "not resolved yet".
    if (observed.hasValue) {
      final book = observed.valueOrNull;
      if (book == null) return const _ItemGoneScaffold();
      return _ItemDetailBody(book: book);
    }
    if (observed.hasError) return const _ItemLoadFailedScaffold();
    final first = initialBook;
    if (first != null && first.id == bookId) {
      return _ItemDetailBody(book: first);
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
class _ItemGoneScaffold extends StatelessWidget {
  const _ItemGoneScaffold();

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
class _ItemLoadFailedScaffold extends StatelessWidget {
  const _ItemLoadFailedScaffold();

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
class _ItemDetailBody extends ConsumerWidget {
  const _ItemDetailBody({required this.book});

  final CatalogueItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
    final vaultKnown =
        session is VaultUnlocked ||
        session is VaultLocked ||
        session is VaultUninitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book'),
        actions: [CatalogueItemActions(book: book)],
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
          // Lend action (S34): rendered whenever the vault state is KNOWN,
          // so a locked vault explains itself instead of silently hiding the
          // feature. Still loading / errored (session == null) → nothing, a
          // transient state, same as before.
          if (vaultKnown) ...[
            const SizedBox(height: 16),
            LendSection(book: book, session: session!),
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
          DeleteForeverButton(book: book),
        ],
      ),
    );
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// Human label for the acquisition source enum (null/`other` handled).
  static String? _sourceLabel(ItemSourceType? type) {
    return switch (type) {
      null => null,
      ItemSourceType.purchased => 'Purchased',
      ItemSourceType.gift => 'Gift',
      ItemSourceType.donated => 'Donated',
      ItemSourceType.inherited => 'Inherited',
      ItemSourceType.other => 'Other',
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

  final CatalogueItem book;

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
              aspectRatioPresets: coverCropPresets,
              // REQUIRED on Android: uCrop only applies a custom preset list
              // when an initial ratio is also given; without this the list is
              // ignored and the default (landscape) presets show instead.
              initAspectRatio: coverCropInitPreset,
            ),
            IOSUiSettings(
              title: 'Crop cover',
              aspectRatioPresets: coverCropPresets,
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
        ItemCover(
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
