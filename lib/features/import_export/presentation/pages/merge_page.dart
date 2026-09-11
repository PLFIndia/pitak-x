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
/// v1 surfaces conflicts / possible-duplicates as COUNTS only (matching the
/// Kotlin app's shipped scope); the per-row keep-mine/take-theirs/keep-both
/// review screen is a deliberate follow-up (`applyResolution` is implemented +
/// unit-tested, it just has no per-row UI yet).
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
            onPressed: busy ? null : _pickAndMerge,
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
          if (mergeState is MergeDone) _ResultView(result: mergeState.result),
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

/// Shown after a merge is applied: the counts.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final MergeResult result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reviewCount =
        result.conflicts.length + result.possibleDuplicates.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Merge complete',
          style: textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 8),
        Text('Books added: ${result.added}'),
        Text('Already matched (no change): ${result.identical}'),
        if (reviewCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$reviewCount book(s) appear on both devices but differ. They were '
            'left unchanged on your device for now \u2014 reviewing each one '
            'pick a version is coming in a later update.',
            style: textTheme.bodySmall?.copyWith(color: scheme.secondary),
          ),
        ],
      ],
    );
  }
}
