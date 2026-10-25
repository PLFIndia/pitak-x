/// The per-row review list of the merge page (presentation, AGENTS.md §3.1)
/// — extracted from `merge_page.dart` in plan S19 so both stay under the
/// 500-line cap (the S14/S15 idiom: split widgets before extending a capped
/// file). Behaviour is unchanged; only the periodical count lines the page
/// gained are new.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_controller.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// The per-row review list (N07): a heading with the open count and one
/// [_ReviewCard] per conflict / possible duplicate.
class MergeReviewSection extends StatelessWidget {
  /// Creates the review section for [done]; [onResolve] applies a choice.
  const MergeReviewSection({
    required this.done,
    required this.onResolve,
    super.key,
  });

  /// The terminal merge state whose review list is rendered.
  final MergeDone done;

  /// Applies a resolution to the row at the given index.
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
    MergeField.kind => 'Kind',
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
    MergeField.issue => 'Issue details',
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
