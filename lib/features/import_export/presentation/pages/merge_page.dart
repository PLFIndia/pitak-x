/// Community-library merge screen (presentation, AGENTS.md §3.1).
///
/// Reconciles another maintainer's exported `.json` library with this device's
/// catalogue (PLAN-merge.md). Flow:
///  1. Pick a Pitak JSON export file (read under the shared bounded-read cap).
///  2. [MergeController] runs the library-ID gate:
///     - IDs MATCH → the add-only union is applied automatically; we show the
///       counts (added / identical / to-review).
///     - IDs DIFFER → we surface a Join (non-destructive, default) vs Overwrite
///       (destructive, behind an explicit confirm) decision.
///
/// N11: the merge state machine lives in [MergeController] (keep-alive,
/// re-entrancy guard, typed terminal states, controller-side library
/// refresh) — this page only renders [MergeUiState] and forwards intents, so
/// navigating away mid-merge can neither crash nor lose the result.
///
/// N07: the result view is an HONEST summary — a replacement is described as
/// a replacement, rows the parser skipped and adjustments it made are listed
/// (same wording as the Import page), and a library identity that could not
/// be adopted after the books landed is called out so the user knows the next
/// merge will ask them to Join again. Every conflict / possible duplicate the
/// engine surfaced is a review card ([_ReviewCard]) showing what differs (or
/// why the row looks like a duplicate) with keep-mine / take-theirs /
/// keep-both actions that go through `MergeController.resolve`. An in-file
/// key collision has no local book to overwrite, so its card offers only
/// skip / add-as-separate.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/bounded_file_read.dart';
import 'package:pitaka/features/import_export/application/merge_controller.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// Screen to merge an incoming library file into the local catalogue.
class MergePage extends ConsumerStatefulWidget {
  /// Creates the merge page.
  const MergePage({super.key});

  @override
  ConsumerState<MergePage> createState() => _MergePageState();
}

class _MergePageState extends ConsumerState<MergePage> {
  /// Page-local failure of the pick/read itself (before the controller is
  /// involved): oversized or unreadable file.
  String? _pickError;

  Future<void> _pickAndMerge() async {
    const group = XTypeGroup(label: 'Pitak library', extensions: ['json']);
    // N11: the picker plugin and the read can throw (platform errors,
    // disappearing files) — fail closed with safe copy instead of an
    // unhandled async error.
    final Uint8List bytes;
    try {
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      // M05/N11: the shared bounded read replaces the old length-then-
      // `readAsString` check — a lying `length()` can no longer buy an
      // unbounded buffer, and malformed UTF-8 is decoded leniently (same as
      // the Import page) so the PARSER rejects it with merge-specific copy.
      final read = await readPickedFileBounded(
        file,
        maxBytes: ImportLimits.defaults.maxTextChars,
      );
      if (read == null) {
        if (!mounted) return;
        setState(() => _pickError = 'File is too large to import safely.');
        return;
      }
      bytes = read;
    } on Object {
      if (!mounted) return;
      setState(
        () => _pickError = 'Could not read that file. Please try again.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _pickError = null);
    // The controller owns the merge from here — nothing after this await
    // touches `ref` or `setState`, so leaving the page mid-merge is safe.
    await ref
        .read(mergeControllerProvider.notifier)
        .mergeText(utf8.decode(bytes, allowMalformed: true));
  }

  Future<void> _overwrite(MergeDiffersDecision decision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your entire library?'),
        content: Text(
          'This deletes all ${decision.localIsEmpty ? '' : 'your '}books on '
          'this device and replaces them with the books from the file. This '
          'cannot be undone. If a borrowers vault exists, unlock it first. '
          'Replacement is allowed only when all existing loan history can '
          'be matched safely to the incoming books. Otherwise nothing is '
          'replaced. The vault and its loan history are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(mergeControllerProvider.notifier).applyOverwrite();
  }

  static String _messageFor(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => 'Merge failed. Please check the file and try again.',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final mergeState = ref.watch(mergeControllerProvider);
    final busy = mergeState is MergeRunning;
    // N07: while one review row is being written the catalogue is mid-change;
    // a new file pick is refused by the controller too — the disabled button
    // just makes that visible.
    final resolving = mergeState is MergeDone && mergeState.isResolving;

    return Scaffold(
      appBar: AppBar(title: const Text('Merge from a file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Combine another maintainer\u2019s library with yours. Pick a '
            'Pitak JSON file they exported. New books are added; books you '
            'both have '
            'are matched and left alone. Nothing is deleted unless you choose '
            'to replace your library.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy || resolving ? null : _pickAndMerge,
            icon: const Icon(Icons.merge_type),
            label: const Text('Choose a library file'),
          ),
          const SizedBox(height: 24),
          if (busy) const Center(child: CircularProgressIndicator.adaptive()),
          if (_pickError != null)
            Text(_pickError!, style: TextStyle(color: scheme.error)),
          if (mergeState is MergeFailed)
            Text(
              _messageFor(mergeState.failure),
              style: TextStyle(color: scheme.error),
            ),
          if (mergeState is MergeNeedsDecision) ...[
            if (mergeState.applyFailure != null)
              Text(
                _messageFor(mergeState.applyFailure!),
                style: TextStyle(color: scheme.error),
              ),
            _DecisionView(
              decision: mergeState.decision,
              onJoin: mergeState.applying
                  ? null
                  : ref.read(mergeControllerProvider.notifier).applyJoin,
              onOverwrite: mergeState.applying
                  ? null
                  : () => _overwrite(mergeState.decision),
            ),
          ],
          if (mergeState is MergeDone) ...[
            _ResultView(result: mergeState.result),
            if (mergeState.review.isNotEmpty)
              _ReviewSection(
                done: mergeState,
                onResolve: ref.read(mergeControllerProvider.notifier).resolve,
              ),
          ],
        ],
      ),
    );
  }
}

/// Shown when the incoming file belongs to a DIFFERENT library (ID mismatch).
class _DecisionView extends StatelessWidget {
  const _DecisionView({
    required this.decision,
    required this.onJoin,
    required this.onOverwrite,
  });

  final MergeDiffersDecision decision;
  final VoidCallback? onJoin;
  final VoidCallback? onOverwrite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final incomingName = decision.incomingLibraryName.isNotEmpty
        ? '\u201c${decision.incomingLibraryName}\u201d'
        : 'another library';

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Different library', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This file is from $incomingName, which is not the same library '
              'as yours. Choose how to combine them:',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onJoin,
              icon: const Icon(Icons.group_add),
              label: const Text('Join (recommended)'),
            ),
            Text(
              'Keep all your books and add theirs. You become one library.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onOverwrite,
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.warning_amber),
              label: const Text('Replace my library'),
            ),
            Text(
              'Delete your books and use theirs instead. Cannot be undone.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after a merge is applied: the counts plus every omission (N07).
/// The review rows themselves are [_ReviewSection], rendered below this.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final MergeResult result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final omissionStyle = textTheme.bodySmall?.copyWith(color: scheme.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.replaced ? 'Library replaced' : 'Merge complete',
          style: textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 8),
        if (result.replaced)
          Text('Books now on this device: ${result.added}')
        else ...[
          Text('Books added: ${result.added}'),
          Text('Already matched (no change): ${result.identical}'),
        ],
        if (result.namespace == MergeNamespaceOutcome.adoptionFailed) ...[
          const SizedBox(height: 8),
          Text(
            'The books were ${result.replaced ? 'replaced' : 'added'}, but '
            'this device could not take on the other library\u2019s identity. '
            'It still counts as a separate library, so the next merge from '
            'that library will ask you to Join again.',
            style: omissionStyle,
          ),
        ],
        if (result.skippedRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Not imported',
            style: textTheme.titleSmall?.copyWith(color: scheme.error),
          ),
          for (final row in result.skippedRows)
            Text('\u2022 $row', style: textTheme.bodySmall),
        ],
        if (result.adjustments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Adjustments', style: textTheme.titleSmall),
          for (final adjustment in result.adjustments)
            Text('\u2022 $adjustment', style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// The per-row review list (N07): a heading with the open count and one
/// [_ReviewCard] per conflict / possible duplicate.
class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.done, required this.onResolve});

  final MergeDone done;
  final Future<void> Function(int index, MergeResolution resolution) onResolve;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final open = done.openCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Needs your review', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          open == 0
              ? 'All ${done.review.length} reviewed.'
              : '$open of ${done.review.length} still to decide. Your books '
                    'are unchanged until you choose.',
          style: textTheme.bodySmall,
        ),
        for (var i = 0; i < done.review.length; i++)
          _ReviewCard(
            item: done.review[i],
            // Only one row writes at a time: every card's actions are off
            // while any row is applying (the controller refuses too).
            enabled: !done.isResolving,
            onResolve: (resolution) => onResolve(i, resolution),
          ),
      ],
    );
  }
}

/// One conflict / possible duplicate with its explanation and actions.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.item,
    required this.enabled,
    required this.onResolve,
  });

  final MergeReviewItem item;
  final bool enabled;
  final void Function(MergeResolution resolution) onResolve;

  /// Long text (an 8000-char note is valid) must not blow up the card.
  static const int _valueMaxLines = 3;

  static String _labelFor(MergeField field) => switch (field) {
    MergeField.title => 'Title',
    MergeField.titleTransliteration => 'Title (Roman script)',
    MergeField.author => 'Author',
    MergeField.isbn => 'ISBN',
    MergeField.publisher => 'Publisher',
    MergeField.publishedYear => 'Year',
    MergeField.genre => 'Genre',
    MergeField.cover => 'Cover link',
    MergeField.pageCount => 'Pages',
    MergeField.language => 'Language',
    MergeField.notes => 'Notes',
    MergeField.location => 'Location',
    MergeField.sourceType => 'Source',
    MergeField.sourceDetail => 'Source details',
    MergeField.ageGroup => 'Age group',
    MergeField.copyCount => 'Copies',
    MergeField.needsMetadata => 'Needs details',
    MergeField.removed => 'Removed',
  };

  static String _headline(MergeReviewItem item) => switch (item.kind) {
    MergeReviewKind.conflict => 'Same book, different details',
    MergeReviewKind.similarTitle => 'Possibly the same book',
    MergeReviewKind.identityKey => 'Already matched to another row',
    MergeReviewKind.inFileCollision => 'Duplicate row in the file',
  };

  static String _explanation(MergeReviewItem item) => switch (item.kind) {
    MergeReviewKind.conflict =>
      'Matched by ${item.matchedBy == MatchKind.isbn ? 'ISBN' : 'identity'}. '
          'Yours \u2192 theirs:',
    MergeReviewKind.similarTitle =>
      'The file has \u201c${item.incoming.title}\u201d, which looks '
          '${(item.similarity * 100).round()}% like your '
          '\u201c${item.local.title}\u201d. Neither has an ISBN, so this '
          'cannot be checked automatically.',
    MergeReviewKind.identityKey =>
      'The file\u2019s \u201c${item.incoming.title}\u201d shares its ISBN or '
          'identity with your \u201c${item.local.title}\u201d, which another '
          'row of the file already matched.',
    MergeReviewKind.inFileCollision =>
      'The file\u2019s \u201c${item.incoming.title}\u201d shares its ISBN or '
          'identity with \u201c${item.local.title}\u201d from the same file, '
          'so only one of them could be added. There is no book of yours to '
          'replace.',
  };

  static String _resolvedLine(
    MergeResolution resolution,
    MergeReviewKind kind,
  ) {
    final collision = kind == MergeReviewKind.inFileCollision;
    return switch (resolution) {
      MergeResolution.keepMine => collision ? 'Skipped.' : 'Kept yours.',
      MergeResolution.takeTheirs => 'Took theirs.',
      MergeResolution.keepBoth =>
        collision
            ? 'Added as a separate book.'
            : 'Kept both as separate books.',
    };
  }

  static String _failureLine(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => 'Could not apply that choice. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = item.status;
    final collision = item.kind == MergeReviewKind.inFileCollision;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_headline(item), style: textTheme.titleSmall),
            const SizedBox(height: 4),
            if (item.kind == MergeReviewKind.conflict)
              Text(
                item.local.title,
                style: textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text(_explanation(item), style: textTheme.bodySmall),
            if (item.kind == MergeReviewKind.conflict) ...[
              const SizedBox(height: 8),
              for (final diff in mergeDifferences(item.local, item.incoming))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_labelFor(diff.field)}: '
                    '${diff.local ?? '(none)'} \u2192 '
                    '${diff.incoming ?? '(none)'}',
                    style: textTheme.bodyMedium,
                    maxLines: _valueMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            switch (status) {
              ReviewApplying() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
              ReviewResolved(:final resolution) => Text(
                _resolvedLine(resolution, item.kind),
                style: textTheme.bodyMedium?.copyWith(color: scheme.primary),
              ),
              ReviewPending() || ReviewFailed() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (status is ReviewFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _failureLine(status.failure),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton(
                        onPressed: enabled
                            ? () => onResolve(MergeResolution.keepMine)
                            : null,
                        child: Text(collision ? 'Skip' : 'Keep mine'),
                      ),
                      if (item.canTakeTheirs)
                        FilledButton.tonal(
                          onPressed: enabled
                              ? () => onResolve(MergeResolution.takeTheirs)
                              : null,
                          child: const Text('Take theirs'),
                        ),
                      OutlinedButton(
                        onPressed: enabled
                            ? () => onResolve(MergeResolution.keepBoth)
                            : null,
                        child: Text(
                          collision ? 'Add as a separate book' : 'Keep both',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}
