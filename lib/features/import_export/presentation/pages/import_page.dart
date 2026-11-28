/// Import screen (presentation layer, AGENTS.md §3.1).
///
/// Two ways in: paste JSON/CSV text, or choose a JSON or CSV file. Both run
/// [ImportController]. A file is chosen through the app's own picker and
/// read by the controller (decision D24): this page never holds a file or
/// its bytes, it only shows a sentence when no file was taken. A file is
/// judged by its first bytes, not by its name: a ZIP is refused with a
/// sentence before it is read (backup rework BR7, decision D29). On success
/// the page shows an [ImportSummary]; the controller refreshes the library
/// + wishlist lists so imported rows appear immediately.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/presentation/picked_file_messages.dart';

String _importErrorMessage(Object error) {
  if (error is SchemaTooNewFailure) {
    return 'This file was created by a newer version of Pitak. '
        'Update the app before importing.';
  }
  return "Couldn't import that. Please check the file and try again.";
}

/// Screen to import a library/wishlist from pasted text or a chosen file.
class ImportPage extends ConsumerStatefulWidget {
  /// Creates the import page.
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final TextEditingController _text = TextEditingController();

  /// Why the chosen file was not taken (too large, a ZIP, could not be
  /// read, …), as a sentence. Shown like a controller error. Null when
  /// there is nothing to say.
  String? _fileError;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _importText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _fileError = null);
    // N11: the controller owns the run AND the post-success list refresh —
    // nothing after this await touches `ref`, so leaving the page mid-import
    // cannot crash and the refresh cannot be lost with the page.
    await ref.read(importControllerProvider.notifier).importText(text);
  }

  Future<void> _importFile() async {
    setState(() => _fileError = null);
    // The controller owns the whole way of the file: the system's picker,
    // the private copy under the size cap, the read, the removal of the
    // copy, and the import (decision D24). It answers only when no file
    // was taken, with the reason.
    //
    // N11: nothing after this await touches `ref`, so leaving the page
    // while the picker is open or the import runs cannot crash.
    final problem = await ref
        .read(importControllerProvider.notifier)
        .importFile();
    if (problem == null || !mounted) return;
    setState(
      () => _fileError = pickedFileProblemMessage(
        problem,
        use: PickedFileUse.import,
        maxBytes: ImportLimits.defaults.maxTextChars,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Paste a Pitak JSON or Goodreads CSV export below, or choose a '
            'file (JSON or CSV).\n\n'
            'Import ADDS to your library — nothing is deleted. A book that is '
            'already here (same Pitak identity) is updated with the '
            'file\u2019s details; one with the same ISBN is skipped. Wishlist '
            'entries with '
            'a matching ISBN are replaced by the file\u2019s version.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Paste export text',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _importText,
                  icon: const Icon(Icons.text_snippet),
                  label: const Text('Import text'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _importFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose file'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (busy) const Center(child: CircularProgressIndicator.adaptive()),
          // A file that was not taken shows its sentence ALONE. The
          // controller still holds the result of the import before, and
          // "too large" directly above an older "Import complete" would
          // read as if the large file had been imported. That result is
          // shown again once the sentence is gone (the next tap clears it).
          if (_fileError != null)
            Text(
              _fileError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            state.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Text(
                _importErrorMessage(error),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (summary) =>
                  summary == null ? const SizedBox.shrink() : _Summary(summary),
            ),
        ],
      ),
    );
  }
}

/// Renders an [ImportSummary] including any per-row parse errors.
class _Summary extends StatelessWidget {
  const _Summary(this.summary);

  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final formatName = switch (summary.format) {
      ImportFormat.pitakaJson => 'Pitak JSON',
      ImportFormat.goodreadsCsv => 'Goodreads CSV',
      ImportFormat.pitakaBundle => 'Pitak bundle',
      null => 'Unknown',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.format == null ? 'Import failed' : 'Import complete',
          style: textTheme.titleMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 8),
        if (summary.format != null) Text('Format: $formatName'),
        Text('Books added: ${summary.booksAdded}'),
        Text('Books updated (same identity): ${summary.booksUpdated}'),
        Text(
          'Books skipped (same ISBN or issue identity): '
          '${summary.booksSkipped}',
        ),
        // W1: only a schema-v4 file can carry periodicals — show the counts
        // only when one did, so a v3/CSV summary reads exactly as before.
        if (summary.periodicalsAdded +
                summary.periodicalsUpdated +
                summary.periodicalsSkipped >
            0) ...[
          Text('Magazine titles added: ${summary.periodicalsAdded}'),
          Text(
            'Magazine titles updated (same identity): '
            '${summary.periodicalsUpdated}',
          ),
          Text(
            'Magazine titles skipped (same ISSN or duplicate key): '
            '${summary.periodicalsSkipped}',
          ),
        ],
        Text('Wishlist added: ${summary.wishlistAdded}'),
        Text('Wishlist replaced: ${summary.wishlistReplaced}'),
        if (summary.parseErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Issues',
            style: textTheme.titleSmall?.copyWith(color: scheme.error),
          ),
          for (final e in summary.parseErrors)
            Text('• $e', style: textTheme.bodySmall),
        ],
        if (summary.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Adjustments', style: textTheme.titleSmall),
          for (final w in summary.warnings)
            Text('• $w', style: textTheme.bodySmall),
        ],
      ],
    );
  }
}
