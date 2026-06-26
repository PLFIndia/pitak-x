/// Export screen (presentation layer, AGENTS.md §3.1).
///
/// Choose a scope (library / wishlist / both) and a format (JSON / CSV / PDF),
/// then save to a file via the platform save dialog. JSON round-trips through
/// the import screen; CSV is a flat library dump; PDF is a printable catalogue
/// of the library (always the library list, with user-selectable columns).
/// Bundle is deferred.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/infrastructure/cover_paths.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Bundled Noto Sans fonts for the PDF export, ordered base-first. The Latin
/// face is the base (covers ASCII/punctuation); the Indic faces are tried in
/// order for strings the base can't encode. Regular + Bold are kept in lockstep
/// so headers (bold) and body (regular) resolve to the same script.
const List<String> _kRegularFonts = [
  'assets/fonts/NotoSans-Regular.ttf',
  'assets/fonts/NotoSansDevanagari-Regular.ttf',
  'assets/fonts/NotoSansTamil-Regular.ttf',
  'assets/fonts/NotoSansBengali-Regular.ttf',
  'assets/fonts/NotoSansTelugu-Regular.ttf',
  'assets/fonts/NotoSansKannada-Regular.ttf',
  'assets/fonts/NotoSansGujarati-Regular.ttf',
  'assets/fonts/NotoSansGurmukhi-Regular.ttf',
  'assets/fonts/NotoSansMalayalam-Regular.ttf',
  'assets/fonts/NotoSansOriya-Regular.ttf',
];

const List<String> _kBoldFonts = [
  'assets/fonts/NotoSans-Bold.ttf',
  'assets/fonts/NotoSansDevanagari-Bold.ttf',
  'assets/fonts/NotoSansTamil-Bold.ttf',
  'assets/fonts/NotoSansBengali-Bold.ttf',
  'assets/fonts/NotoSansTelugu-Bold.ttf',
  'assets/fonts/NotoSansKannada-Bold.ttf',
  'assets/fonts/NotoSansGujarati-Bold.ttf',
  'assets/fonts/NotoSansGurmukhi-Bold.ttf',
  'assets/fonts/NotoSansMalayalam-Bold.ttf',
  'assets/fonts/NotoSansOriya-Bold.ttf',
];

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
  bool _busy = false;
  String? _status;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final useCase = await ref.read(exportLibraryUseCaseProvider.future);
      // CSV is library-only; PDF is always the library list regardless of
      // scope.
      final scope = _format == ExportFormat.csv
          ? ExportScope.libraryOnly
          : _scope;

      // Resolve the PDF inputs (library name + bundled app icon) only for PDF.
      final isPdf = _format == ExportFormat.pdf;
      final isJson = _format == ExportFormat.json;
      // The library name rides the PDF header AND the JSON merge envelope.
      final libraryName = (isPdf || isJson)
          ? ref
                .read(settingsControllerProvider)
                .maybeWhen(data: (s) => s.libraryName, orElse: () => '')
          : '';
      // Mint/read this app's library ID so every JSON export carries one
      // (PLAN-merge.md D40 — no "file has no library ID" edge case for us).
      final libraryId = isJson
          ? await ref
                .read(settingsControllerProvider.notifier)
                .getOrCreateLibraryId()
          : '';
      final footerIcon = isPdf ? await _loadFooterIcon() : null;
      final logoBytes = isPdf ? await _loadLibraryLogo() : null;
      // Shaped-image PDF text: Flutter's engine shapes complex scripts right
      // (Devanagari half-letters / matra reordering) where `drawString` cannot.
      // The rasterizer registers + uses the bundled Noto fonts itself, so the
      // old per-string TTF byte bundles are no longer needed on the PDF path.
      final rasterizer = isPdf
          ? UiPdfTextRasterizer(
              regularAssets: _kRegularFonts,
              boldAssets: _kBoldFonts,
            )
          : null;

      final result = await useCase(
        scope: scope,
        format: _format,
        pdfColumns: isPdf
            ? PdfColumn.order.where(_pdfColumns.contains).toList()
            : null,
        libraryName: libraryName,
        libraryId: libraryId,
        footerIconBytes: footerIcon,
        logoBytes: logoBytes,
        textRasterizer: rasterizer,
      );

      final export = result.toNullable();
      if (result.isLeft() || export == null) {
        if (mounted) setState(() => _status = 'Export failed.');
        return;
      }

      final share = ref.read(fileShareServiceProvider);
      final outcome = await share.shareBytes(
        bytes: export.bytes,
        fileName: export.suggestedFileName,
        mimeType: export.mimeType,
        sharePositionOrigin: _shareOrigin(),
      );
      if (!mounted) return;
      setState(() {
        _status = switch (outcome) {
          ShareOutcome.success => 'Shared ${export.suggestedFileName}.',
          ShareOutcome.dismissed => null,
          ShareOutcome.unavailable => 'Sharing is unavailable on this device.',
        };
      });
    } on Object {
      if (mounted) setState(() => _status = 'Export failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The source rect for the iPad share popover (ignored on phones).
  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<Uint8List?> _loadFooterIcon() async {
    try {
      final data = await rootBundle.load('assets/pdf/app_icon.png');
      return data.buffer.asUint8List();
    } on Object {
      // A missing icon must not block the export; the footer just omits it.
      return null;
    }
  }

  /// Resolves the user's library logo to bytes for the PDF header, or null when
  /// none is set / the file is missing. Reuses [CoverPaths] + the covers dir
  /// exactly like the `LibraryLogo` widget (single source of truth); the image
  /// stays on-device. A missing/unreadable logo never blocks the export — the
  /// header just shows the library name without a mark.
  Future<Uint8List?> _loadLibraryLogo() async {
    try {
      final logoRef = ref
          .read(settingsControllerProvider)
          .maybeWhen(data: (s) => s.libraryLogo, orElse: () => '');
      final leaf = CoverPaths.leafOf(logoRef);
      if (leaf == null) return null;
      final coversDir = await ref.read(coversDirProvider.future);
      final file = File(p.join(coversDir, leaf));
      if (!file.existsSync()) return null;
      return file.readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final csv = _format == ExportFormat.csv;
    final pdf = _format == ExportFormat.pdf;
    final scopeLocked = csv || pdf; // both formats are library-only

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
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: const Text('Export to file'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: textTheme.bodyMedium),
          ],
        ],
      ),
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
