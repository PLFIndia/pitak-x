/// Export screen (presentation layer, AGENTS.md §3.1).
///
/// Choose a scope (library / wishlist / both) and a format (JSON / CSV / PDF),
/// then save to a file via the platform share sheet. JSON round-trips through
/// the import screen; CSV is a flat library dump; PDF is a printable catalogue
/// of the library (always the library list, with user-selectable columns).
///
/// CSV and PDF can be narrowed by provenance ("Books to include"): a source
/// type chip (Purchased / Gift / Donated / …) and, under it, a picker of the
/// source details already recorded for that type (donor names, shops), so a
/// librarian can print "everything Ram Sharma donated" without typing — and
/// without typos, since the values come from the catalogue itself.
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
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/export_source_filter.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

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
  // Which books a CSV/PDF includes (JSON always exports everything).
  ExportSourceFilter _sourceFilter = const ExportSourceFilter.all();

  void _export() {
    final filtered = _format != ExportFormat.json;
    // Fire and forget: the controller owns the run and publishes its state;
    // the page reacts through `ref.watch` below, so nothing here needs to
    // survive an await (N11).
    ref
        .read(exportControllerProvider.notifier)
        .export(
          scope: _scope,
          format: _format,
          sourceFilter: filtered
              ? _sourceFilter
              : const ExportSourceFilter.all(),
          pdfColumns: _format == ExportFormat.pdf
              ? PdfColumn.order.where(_pdfColumns.contains).toList()
              : null,
          sharePositionOrigin: _shareOrigin(),
        );
  }

  /// Picking a type (or "All") resets the detail: a donor name belongs to
  /// "donated", it means nothing under "purchased".
  void _pickSourceType(BookSourceType? type) => setState(() {
    _sourceFilter = type == null
        ? const ExportSourceFilter.all()
        : ExportSourceFilter.byType(type);
  });

  /// [detail] null = "any detail" within the already-chosen type.
  void _pickSourceDetail(String? detail) {
    final type = _sourceFilter.sourceType;
    if (type == null) return; // no type chosen: nothing to narrow
    setState(() {
      _sourceFilter = ExportSourceFilter.byType(type, detail: detail);
    });
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

    // Keep the chosen detail honest: if the catalogue changes underneath
    // (a donor renamed on the edit screen) and the picked value no longer
    // exists, fall back to "any detail" instead of silently exporting an
    // empty list. Listening here (not in the picker) keeps the page the
    // single owner of the filter state.
    final chosenType = _sourceFilter.sourceType;
    final chosenDetail = _sourceFilter.sourceDetail;
    if (chosenType != null && chosenDetail != null) {
      ref.listen(librarySourceDetailsProvider(chosenType), (_, next) {
        final details = next.valueOrNull;
        if (details != null && !details.contains(chosenDetail)) {
          _pickSourceDetail(null);
        }
      });
    }

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
          // Provenance filter: CSV + PDF only. JSON is the backup format and
          // always carries the whole library (see ExportLibraryUseCase).
          if (csv || pdf) ...[
            const SizedBox(height: 24),
            Text('Books to include', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Narrow the list by how the books came to you — for example '
              'everything one person donated.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _SourceTypeChips(
              selected: _sourceFilter.sourceType,
              onPick: running ? null : _pickSourceType,
            ),
            if (chosenType != null) ...[
              const SizedBox(height: 8),
              _SourceDetailPicker(
                type: chosenType,
                selected: chosenDetail,
                onChanged: running ? null : _pickSourceDetail,
              ),
            ],
          ],
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

/// "All sources" plus one ChoiceChip per [BookSourceType]; exactly one is
/// selected (null = all).
class _SourceTypeChips extends StatelessWidget {
  const _SourceTypeChips({required this.selected, required this.onPick});

  final BookSourceType? selected;
  final ValueChanged<BookSourceType?>? onPick;

  @override
  Widget build(BuildContext context) {
    final enabled = onPick != null;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        ChoiceChip(
          key: const Key('export-source-all'),
          label: const Text('All sources'),
          selected: selected == null,
          onSelected: enabled ? (_) => onPick!(null) : null,
        ),
        for (final type in BookSourceType.values)
          ChoiceChip(
            key: Key('export-source-${type.name}'),
            label: Text(sourceTypeLabel(type)),
            selected: selected == type,
            onSelected: enabled ? (_) => onPick!(type) : null,
          ),
      ],
    );
  }
}

/// Dropdown of the source details already recorded under [type] (the
/// repository facet), with "Any" first. Reads the facet provider itself so
/// the page does not have to thread an `AsyncValue` through.
///
/// A dropdown must have EXACTLY one item matching its value, so "Any" is
/// represented by the empty string — a value no real detail can have (the
/// facet excludes blanks) — rather than null, which the widget would treat
/// as "nothing selected".
class _SourceDetailPicker extends ConsumerWidget {
  const _SourceDetailPicker({
    required this.type,
    required this.selected,
    required this.onChanged,
  });

  static const String _any = '';

  final BookSourceType type;
  final String? selected;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final details = ref.watch(librarySourceDetailsProvider(type));
    return details.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(key: Key('export-source-loading')),
      ),
      // The provider already degrades a repository failure to an empty list;
      // this branch only catches a thrown bug. Fixed copy, no raw error (§5).
      error: (_, _) =>
          Text('Could not load source details.', style: textTheme.bodySmall),
      data: (values) {
        if (values.isEmpty) {
          return Text(
            'No source details recorded under ${sourceTypeLabel(type)}; '
            'every ${sourceTypeLabel(type).toLowerCase()} book is included.',
            key: const Key('export-source-detail-empty'),
            style: textTheme.bodySmall,
          );
        }
        // The page resets a vanished detail via its listener; until that
        // rebuild lands, show "Any" rather than trip the dropdown's assert.
        final current = (selected != null && values.contains(selected))
            ? selected!
            : _any;
        return DropdownButtonFormField<String>(
          // Keyed per type: switching Donated → Purchased swaps the item
          // list, so the field state starts fresh instead of carrying a
          // value the new list does not contain.
          key: ValueKey('export-source-detail-${type.name}'),
          initialValue: current,
          decoration: const InputDecoration(
            labelText: 'Source detail',
            helperText: 'Donor, shop, person… as recorded on the books.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: _any, child: Text('Any')),
            for (final value in values)
              DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (value) => onChanged!(value == _any ? null : value),
        );
      },
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
