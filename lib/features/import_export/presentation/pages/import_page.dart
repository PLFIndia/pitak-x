/// Import screen (presentation layer, AGENTS.md §3.1).
///
/// Two ways in: paste JSON/CSV text, or pick a file (JSON/CSV/Pitaka bundle
/// .zip). Both run [ImportController]; file content is routed by magic bytes,
/// not filename. On success it shows an [ImportSummary] and refreshes the
/// library + wishlist lists so imported rows appear immediately.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/import_format_sniffer.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';

/// Screen to import a library/wishlist from pasted text or a chosen file.
class ImportPage extends ConsumerStatefulWidget {
  /// Creates the import page.
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _refreshLists() async {
    await ref.read(libraryControllerProvider.notifier).refresh();
    await ref.read(wishlistControllerProvider.notifier).refresh();
  }

  Future<void> _importText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    await ref.read(importControllerProvider.notifier).importText(text);
    if (ref.read(importControllerProvider).hasValue) await _refreshLists();
  }

  Future<void> _importFile() async {
    const group = XTypeGroup(
      label: 'Library export',
      extensions: ['json', 'csv', 'zip', 'pitabundle'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref.read(importControllerProvider.notifier).importBytes(bytes);
    if (ref.read(importControllerProvider).hasValue) await _refreshLists();
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
            'file (JSON, CSV, or a Pitak bundle).',
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
          state.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(
              "Couldn't import that. Please check the file and try again.",
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
        Text('Books skipped (already owned): ${summary.booksSkipped}'),
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
      ],
    );
  }
}
