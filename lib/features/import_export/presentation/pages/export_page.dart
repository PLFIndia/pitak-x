/// Export screen (presentation layer, AGENTS.md §3.1).
///
/// Choose a scope (library / wishlist / both) and a format (JSON / CSV / PDF),
/// then save to a file via the platform share sheet. JSON round-trips through
/// the import screen; CSV is a flat library dump; PDF is a printable catalogue
/// of the library (always the library list, with user-selectable columns).
///
/// Pure presentation: the whole export pipeline (input resolution, use-case
/// invocation, share flow) lives in `ExportController`; this widget collects
/// choices and maps the typed outcome to copy.
///
/// N10-e: while a run is in flight the page watches the controller's
/// `ExportRunning` progress (a determinate bar + "page P · R of N books" for
/// PDF; indeterminate for JSON/CSV) and offers a Cancel button. The run
/// itself survives navigation (controller keep-alive), so coming back shows
/// the live progress or the finished outcome.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';

/// Screen to export the library/wishlist to a file.
class ExportPage extends ConsumerStatefulWidget {
  /// Creates the export page.
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  ExportScope _scope = ExportScope.both;
  ExportFormat _format = ExportFormat.json;
  // PDF column selection (Title is mandatory and always included).
  final Set<PdfColumn> _pdfColumns = PdfColumn.defaultSelection.toSet();

  void _export() {
    // Fire and forget: the controller owns the run and publishes its state;
    // the page reacts through `ref.watch` below, so nothing here needs to
    // survive an await (N11).
    ref
        .read(exportControllerProvider.notifier)
        .export(
          scope: _scope,
          format: _format,
          pdfColumns: _format == ExportFormat.pdf
              ? PdfColumn.order.where(_pdfColumns.contains).toList()
              : null,
          sharePositionOrigin: _shareOrigin(),
        );
  }

  void _cancel() => ref.read(exportControllerProvider.notifier).cancel();

  static String? _statusFor(ExportRunResult result) => switch (result.outcome) {
    ExportOutcome.shared => 'Shared ${result.fileName}.',
    ExportOutcome.dismissed => null,
    ExportOutcome.shareUnavailable => 'Sharing is unavailable on this device.',
    ExportOutcome.failed => 'Export failed.',
    ExportOutcome.cancelled => 'Export cancelled.',
  };

  /// The source rect for the iPad share popover (ignored on phones).
  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final csv = _format == ExportFormat.csv;
    final pdf = _format == ExportFormat.pdf;
    final scopeLocked = csv || pdf; // both formats are library-only

    final runState = ref.watch(exportControllerProvider);
    final running = runState is ExportRunning;
    final status = switch (runState) {
      ExportFinished(:final result) => _statusFor(result),
      ExportIdle() || ExportRunning() => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Format', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(value: ExportFormat.json, label: Text('JSON')),
              ButtonSegment(value: ExportFormat.csv, label: Text('CSV')),
              ButtonSegment(value: ExportFormat.pdf, label: Text('PDF')),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 8),
          Text(switch (_format) {
            ExportFormat.json => 'JSON can be re-imported with no data loss.',
            ExportFormat.csv =>
              'CSV exports the library as a flat spreadsheet.',
            ExportFormat.pdf =>
              'PDF is a printable catalogue of your library. Choose which '
                  'columns appear below — Title is always included.',
          }, style: textTheme.bodySmall),
          const SizedBox(height: 24),
          Text('Include', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          // Scope only applies to JSON; CSV + PDF are library-only.
          SegmentedButton<ExportScope>(
            segments: const [
              ButtonSegment(
                value: ExportScope.libraryOnly,
                label: Text('Library'),
              ),
              ButtonSegment(
                value: ExportScope.wishlistOnly,
                label: Text('Wishlist'),
              ),
              ButtonSegment(value: ExportScope.both, label: Text('Both')),
            ],
            selected: {if (scopeLocked) ExportScope.libraryOnly else _scope},
            onSelectionChanged: scopeLocked
                ? null
                : (s) => setState(() => _scope = s.first),
          ),
          if (pdf) ...[
            const SizedBox(height: 24),
            Text('PDF columns', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Location and Source reveal where/how you got a book; they are '
              'off by default so a shared PDF stays private.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _PdfColumnPicker(
              selected: _pdfColumns,
              onToggle: (col) => setState(() {
                if (_pdfColumns.contains(col)) {
                  _pdfColumns.remove(col);
                } else {
                  _pdfColumns.add(col);
                }
              }),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: running ? null : _export,
            icon: running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: const Text('Export to file'),
          ),
          if (runState is ExportRunning) ...[
            const SizedBox(height: 16),
            _ExportProgress(state: runState, onCancel: _cancel),
          ],
          if (status != null) ...[
            const SizedBox(height: 16),
            Text(status, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Progress bar + counter + Cancel for an in-flight export (N10-e).
class _ExportProgress extends StatelessWidget {
  const _ExportProgress({required this.state, required this.onCancel});

  final ExportRunning state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = state.progress;
    final label = p == null
        ? 'Preparing export…'
        : 'Rendering page ${p.pagesDone} · ${p.rowsDone} of ${p.rowsTotal} '
              'books';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          key: const Key('export-progress'),
          // null = indeterminate (before the first report / non-PDF).
          value: p?.fraction,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodySmall,
                key: const Key('export-progress-label'),
              ),
            ),
            OutlinedButton(
              key: const Key('export-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Wrapping grid of FilterChips for choosing PDF columns. The mandatory Title
/// column is always shown selected and cannot be toggled off.
class _PdfColumnPicker extends StatelessWidget {
  const _PdfColumnPicker({required this.selected, required this.onToggle});

  final Set<PdfColumn> selected;
  final ValueChanged<PdfColumn> onToggle;

  @override
  Widget build(BuildContext context) {
    final labels = defaultPdfLabels().header;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final col in PdfColumn.order)
          FilterChip(
            label: Text(labels[col] ?? col.name),
            selected: col == PdfColumn.mandatory || selected.contains(col),
            onSelected: col == PdfColumn.mandatory
                ? null
                : (_) => onToggle(col),
          ),
      ],
    );
  }
}
