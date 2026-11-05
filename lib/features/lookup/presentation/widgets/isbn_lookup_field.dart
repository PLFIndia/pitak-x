/// Shared ISBN input, scan and lookup presentation for the Add book and Add
/// to wishlist forms. Keeping the row and scan flow here avoids two copies
/// drifting apart (and keeps the already-large form files focused).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Reads the shared opt-in once. Unavailable settings fail closed to manual
/// lookup, so a scan can never cause an unexpected network request.
Future<bool> shouldLookupIsbnAfterScan(WidgetRef ref) async {
  final settings = await ref.read(settingsControllerProvider.notifier).loaded();
  return settings.fold((_) => false, (s) => s.lookupIsbnAfterScan);
}

/// Opens the ISBN scanner, normalizes the result into [onScanned], and calls
/// [lookup] only when the user enabled "Look up ISBN after scanning".
///
/// Default or unavailable settings fail closed to manual mode: no lookup
/// request is made until the user taps the form's Lookup button. Scanning
/// never saves the item. The caller owns the actual lookup and its safe copy.
Future<void> scanIsbnForForm({
  required BuildContext context,
  required WidgetRef ref,
  required void Function(String isbn) onScanned,
  required Future<void> Function() lookup,
  IsbnScannerBuilder? buildScanner,
}) async {
  final scanned = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => ScannerPage(buildScanner: buildScanner),
    ),
  );
  if (scanned == null || !context.mounted) return;
  onScanned(IsbnFormat.normalize(scanned));
  final lookupAfterScan = await shouldLookupIsbnAfterScan(ref);
  if (!context.mounted) return;
  if (lookupAfterScan) await lookup();
}

/// ISBN text field with Scan barcode and Look up details actions.
class IsbnLookupField extends StatelessWidget {
  /// Creates the shared ISBN row.
  const IsbnLookupField({
    required this.controller,
    required this.looking,
    required this.onScan,
    required this.onLookup,
    super.key,
  });

  /// The form's ISBN controller.
  final TextEditingController controller;

  /// Whether a lookup is in flight (both actions are then disabled).
  final bool looking;

  /// Opens the scanner.
  final VoidCallback onScan;

  /// Looks up the current ISBN explicitly.
  final VoidCallback onLookup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'ISBN',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: looking ? null : onScan,
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: 'Look up details',
            icon: looking
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            onPressed: looking ? null : onLookup,
          ),
        ],
      ),
    );
  }
}
