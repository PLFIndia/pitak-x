/// Community-library merge screen (presentation, AGENTS.md §3.1).
///
/// Reconciles another maintainer's exported `.json` library with this device's
/// catalogue (PLAN-merge.md). Flow:
///  1. Pick a Pitak JSON export file.
///  2. The use case runs the library-ID gate:
///     - IDs MATCH → the add-only union is applied automatically; we show the
///       counts (added / identical / to-review).
///     - IDs DIFFER → we surface a Join (non-destructive, default) vs Overwrite
///       (destructive, behind an explicit confirm) decision.
///
/// v1 surfaces conflicts / possible-duplicates as COUNTS only (matching the
/// Kotlin app's shipped scope); the per-row keep-mine/take-theirs/keep-both
/// review screen is a deliberate follow-up (`applyResolution` is implemented +
/// unit-tested, it just has no per-row UI yet).
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';

/// Screen to merge an incoming library file into the local catalogue.
class MergePage extends ConsumerStatefulWidget {
  /// Creates the merge page.
  const MergePage({super.key});

  @override
  ConsumerState<MergePage> createState() => _MergePageState();
}

class _MergePageState extends ConsumerState<MergePage> {
  bool _busy = false;
  String? _error;
  MergeResult? _result;
  MergeDiffersDecision? _decision;

  Future<void> _refreshLibrary() async {
    await ref.read(libraryControllerProvider.notifier).refresh();
  }

  void _reset() {
    setState(() {
      _error = null;
      _result = null;
      _decision = null;
    });
  }

  Future<void> _pickAndMerge() async {
    const group = XTypeGroup(label: 'Pitak library', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    _reset();
    setState(() => _busy = true);
    try {
      final text = await file.readAsString();
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final res = await useCase.call(text);
      res.match((failure) => setState(() => _error = _messageFor(failure)), (
        outcome,
      ) {
        switch (outcome) {
          case MergeMerged(:final result):
            setState(() => _result = result);
            _refreshLibrary();
          case MergeDiffersDecision():
            setState(() => _decision = outcome);
        }
      });
    } on Object {
      setState(() => _error = "Couldn't read that file. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final decision = _decision;
    if (decision == null) return;
    setState(() => _busy = true);
    try {
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final res = await useCase.applyJoin(decision);
      res.match((failure) => setState(() => _error = _messageFor(failure)), (
        result,
      ) {
        setState(() {
          _decision = null;
          _result = result;
        });
        _refreshLibrary();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _overwrite() async {
    final decision = _decision;
    if (decision == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your entire library?'),
        content: Text(
          'This deletes all ${decision.localIsEmpty ? '' : 'your '}books on '
          'this device and replaces them with the books from the file. This '
          'cannot be undone. Your borrowers vault is not affected.',
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
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final res = await useCase.applyOverwrite(decision);
      res.match((failure) => setState(() => _error = _messageFor(failure)), (
        _,
      ) {
        setState(() {
          _decision = null;
          _result = const MergeResult(
            added: 0,
            identical: 0,
            conflicts: [],
            possibleDuplicates: [],
          );
        });
        _refreshLibrary();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _messageFor(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => 'Merge failed. Please check the file and try again.',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

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
            onPressed: _busy ? null : _pickAndMerge,
            icon: const Icon(Icons.merge_type),
            label: const Text('Choose a library file'),
          ),
          const SizedBox(height: 24),
          if (_busy) const Center(child: CircularProgressIndicator.adaptive()),
          if (_error != null)
            Text(_error!, style: TextStyle(color: scheme.error)),
          if (_decision != null)
            _DecisionView(
              decision: _decision!,
              onJoin: _busy ? null : _join,
              onOverwrite: _busy ? null : _overwrite,
            ),
          if (_result != null) _ResultView(result: _result!),
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
